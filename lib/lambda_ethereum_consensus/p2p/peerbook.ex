defmodule LambdaEthereumConsensus.P2P.Peerbook do
  @moduledoc """
  General peer bookkeeping.
  """
  require Logger
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.Store.KvSchema
  alias LambdaEthereumConsensus.Utils

  @initial_score 100
  @penalizing_score 15
  @target_peers 128
  @max_prune_size 8
  @prune_percentage 0.05

  @metadata_protocol_id "/eth2/beacon_chain/req/metadata/2/ssz_snappy"

  use KvSchema, prefix: "peerbook"

  @impl KvSchema
  @spec encode_key(String.t()) :: {:ok, binary()} | {:error, binary()}
  def encode_key(key), do: {:ok, key}

  @impl KvSchema
  @spec decode_key(binary()) :: {:ok, String.t()} | {:error, binary()}
  def decode_key(key), do: {:ok, key}

  @impl KvSchema
  @spec encode_value(map()) :: {:ok, binary()} | {:error, binary()}
  def encode_value(peerbook), do: {:ok, :erlang.term_to_binary(peerbook)}

  @impl KvSchema
  @spec decode_value(binary()) :: {:ok, map()} | {:error, binary()}
  def decode_value(bin), do: {:ok, :erlang.binary_to_term(bin)}

  @doc """
    Initializes the table in the db by storing an empty peerbook.
  """
  def init() do
    store_peerbook(%{})
  end

  @doc """
  Get some peer from the peerbook.
  """
  def get_some_peer() do
    # TODO: This is a very naive implementation of a peer selection algorithm,
    # this sorts the peers every time. The same is true for the pruning.
    peerbook = fetch_peerbook!()

    if peerbook == %{} do
      nil
    else
      peerbook
      |> Enum.sort_by(fn {_peer_id, score} -> -score end)
      |> Enum.take(5)
      |> Enum.random()
      |> elem(0)
    end
  end

  def penalize_peer(peer_id) do
    Logger.debug("[Peerbook] Penalizing peer: #{inspect(Utils.format_shorten_binary(peer_id))}")

    peer_score = fetch_peerbook!() |> Map.get(peer_id)
    penalizing_score = penalizing_score()

    case peer_score do
      nil ->
        :ok

      score when score - penalizing_score <= 0 ->
        Logger.debug("[Peerbook] Removing peer: #{inspect(Utils.format_shorten_binary(peer_id))}")

        fetch_peerbook!()
        |> Map.delete(peer_id)
        |> store_peerbook()

      score ->
        fetch_peerbook!()
        |> Map.put(peer_id, score - penalizing_score)
        |> store_peerbook()
    end
  end

  def handle_new_peer(peer_id) do
    peerbook = fetch_peerbook!()

    Logger.debug(
      "[Peerbook] New peer connected: #{inspect(Utils.format_shorten_binary(peer_id))}"
    )

    if not Map.has_key?(peerbook, peer_id) do
      :telemetry.execute([:peers, :connection], %{id: peer_id}, %{result: "success"})
      Map.put(peerbook, peer_id, @initial_score) |> store_peerbook()
    end

    prune()
  end

  def challenge_peer(peer_id) do
    case Libp2pPort.send_request(peer_id, @metadata_protocol_id, "") do
      {:ok, <<0, 17>> <> _payload} ->
        :telemetry.execute([:peers, :challenge], %{}, %{result: "passed"})

      _ ->
        :telemetry.execute([:peers, :challenge], %{}, %{result: "failed"})
        penalize_peer(peer_id)
    end
  end

  defp prune() do
    peerbook = fetch_peerbook!()
    len = map_size(peerbook)
    prune_size = if len > 0, do: calculate_prune_size(len), else: 0

    if prune_size > 0 do
      Logger.debug("[Peerbook] Pruning #{prune_size} peers by challenge")

      n = :rand.uniform(len)

      peerbook
      |> Map.keys()
      |> Stream.drop(n)
      |> Stream.take(prune_size)
      |> Enum.each(fn peer_id -> Task.start(__MODULE__, :challenge_peer, [peer_id]) end)
    end
  end

  defp calculate_prune_size(len) do
    (len * @prune_percentage)
    |> round()
    |> min(@max_prune_size)
    |> min(len - @target_peers)
    |> max(0)
  end

  defp store_peerbook(peerbook), do: put("", peerbook)

  defp fetch_peerbook(), do: get("")

  defp fetch_peerbook!() do
    {:ok, peerbook} = fetch_peerbook()
    peerbook
  end

  defp penalizing_score() do
    :lambda_ethereum_consensus
    |> Application.get_env(__MODULE__)
    |> Keyword.get(:penalizing_score, @penalizing_score)
  end
end
