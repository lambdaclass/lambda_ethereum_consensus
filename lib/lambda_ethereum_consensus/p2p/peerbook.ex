defmodule LambdaEthereumConsensus.P2P.Peerbook do
  @moduledoc """
  General peer bookkeeping.
  """
  require Logger
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.Store.KvSchema

  @initial_score 100
  @penalize 20
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
    # TODO: This is a very naive implementation of a peer selection algorithm.
    peerbook = fetch_peerbook!()

    if peerbook == %{} do
      nil
    else
      peerbook
      |> Enum.sort_by(fn {_peer_id, score} -> score end)
      |> Enum.take(4)
      |> Enum.random()
      |> elem(0)
    end
  end

  def penalize_peer(peer_id) do
    Logger.debug(
      "Penalizing peer: #{inspect(LambdaEthereumConsensus.Utils.format_shorten_binary(peer_id))}"
    )

    peer_score = fetch_peerbook!() |> Map.get(peer_id)

    case peer_score do
      nil ->
        :ok

      score when score - @penalize <= 0 ->
        Logger.info(
          "Removing peer: #{inspect(LambdaEthereumConsensus.Utils.format_shorten_binary(peer_id))}"
        )

        fetch_peerbook!()
        |> Map.delete(peer_id)
        |> store_peerbook()

      score ->
        fetch_peerbook!()
        |> Map.put(peer_id, score - @penalize)
        |> store_peerbook()
    end
  end

  def handle_new_peer(peer_id) do
    peerbook = fetch_peerbook!()

    Logger.debug(
      "New peer connected: #{inspect(LambdaEthereumConsensus.Utils.format_shorten_binary(peer_id))}"
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

    if len != 0 do
      prune_size =
        (len * @prune_percentage)
        |> round()
        |> min(@max_prune_size)
        |> min(len - @target_peers)
        |> max(0)

      n = :rand.uniform(len)

      peerbook
      |> Map.keys()
      |> Stream.drop(n)
      |> Stream.take(prune_size)
      |> Enum.each(fn peer_id -> Task.start(__MODULE__, :challenge_peer, [peer_id]) end)
    end
  end

  defp store_peerbook(peerbook), do: put("", peerbook)

  defp fetch_peerbook(), do: get("")

  defp fetch_peerbook!() do
    {:ok, peerbook} = fetch_peerbook()
    peerbook
  end
end
