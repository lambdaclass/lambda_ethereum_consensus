defmodule LambdaEthereumConsensus.P2P.Peerbook do
  @moduledoc """
  General peer bookkeeping.
  """
  require Logger
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.ReqResp
  alias LambdaEthereumConsensus.StateTransition.DasCore
  alias LambdaEthereumConsensus.Store.KvSchema
  alias LambdaEthereumConsensus.Utils

  @initial_score 100
  @penalizing_score 15
  @target_peers 128
  @max_prune_size 8
  @prune_percentage 0.05

  if HardForkAliasInjection.fulu?() do
    @metadata_protocol_id "/eth2/beacon_chain/req/metadata/3/ssz_snappy"
  else
    @metadata_protocol_id "/eth2/beacon_chain/req/metadata/2/ssz_snappy"
  end

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
      |> Enum.sort_by(fn {_peer_id, %{score: score}} -> -score end)
      |> Enum.take(5)
      |> Enum.random()
      |> elem(0)
    end
  end

  @doc "Get a peer that custodies the given column index."
  def get_peer_for_column(column_index) do
    peerbook = fetch_peerbook!()

    peerbook
    |> Enum.filter(fn {_id, %{node_id: nid, custody_group_count: cgc}} ->
      nid != nil and cgc != nil and
        column_index in DasCore.get_custody_columns(:binary.decode_unsigned(nid), cgc)
    end)
    |> case do
      [] ->
        nil

      peers ->
        peers
        |> Enum.sort_by(fn {_id, %{score: s}} -> -s end)
        |> Enum.take(5)
        |> Enum.random()
        |> elem(0)
    end
  end

  @doc "Get any peer known to support PeerDAS (has custody_group_count set)."
  def get_peerdas_peer() do
    peerbook = fetch_peerbook!()

    peerbook
    |> Enum.filter(fn {_id, %{custody_group_count: cgc}} -> cgc != nil end)
    |> case do
      [] ->
        nil

      peers ->
        peers
        |> Enum.sort_by(fn {_id, %{score: s}} -> -s end)
        |> Enum.take(5)
        |> Enum.random()
        |> elem(0)
    end
  end

  def penalize_peer(peer_id) do
    Logger.debug("[Peerbook] Penalizing peer: #{inspect(Utils.format_shorten_binary(peer_id))}")

    entry = fetch_peerbook!() |> Map.get(peer_id)
    penalizing_score = penalazing_score()

    case entry do
      nil ->
        :ok

      %{score: score} when score - penalizing_score <= 0 ->
        Logger.debug("[Peerbook] Removing peer: #{inspect(Utils.format_shorten_binary(peer_id))}")

        fetch_peerbook!()
        |> Map.delete(peer_id)
        |> store_peerbook()

      %{score: score} ->
        fetch_peerbook!()
        |> Map.update!(peer_id, fn e -> %{e | score: score - penalizing_score} end)
        |> store_peerbook()
    end
  end

  def handle_new_peer(peer_id, node_id \\ nil) do
    peerbook = fetch_peerbook!()

    Logger.debug(
      "[Peerbook] New peer connected: #{inspect(Utils.format_shorten_binary(peer_id))}"
    )

    if not Map.has_key?(peerbook, peer_id) do
      :telemetry.execute([:peers, :connection], %{id: peer_id}, %{result: "success"})
      entry = %{score: @initial_score, node_id: node_id, custody_group_count: nil}
      Map.put(peerbook, peer_id, entry) |> store_peerbook()
      Task.start(__MODULE__, :challenge_peer, [peer_id])
    end

    prune()
  end

  def challenge_peer(peer_id) do
    case Libp2pPort.send_request(peer_id, @metadata_protocol_id, "") do
      {:ok, <<0, _::binary>> = response} ->
        :telemetry.execute([:peers, :challenge], %{}, %{result: "passed"})
        parse_and_store_peer_metadata(peer_id, response)

      _ ->
        :telemetry.execute([:peers, :challenge], %{}, %{result: "failed"})
        penalize_peer(peer_id)
    end
  end

  defp parse_and_store_peer_metadata(peer_id, response) do
    case ReqResp.decode_response_chunk(response, Types.Metadata) do
      {:ok, metadata} ->
        cgc = Map.get(metadata, :custody_group_count)

        if cgc != nil do
          Logger.debug(
            "[Peerbook] PeerDAS peer discovered, custody_group_count=#{cgc}: #{inspect(Utils.format_shorten_binary(peer_id))}"
          )

          fetch_peerbook!()
          |> Map.update(
            peer_id,
            %{score: @initial_score, node_id: nil, custody_group_count: cgc},
            fn e -> %{e | custody_group_count: cgc} end
          )
          |> store_peerbook()
        end

      _ ->
        :ok
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

  defp penalazing_score() do
    :lambda_ethereum_consensus
    |> Application.get_env(__MODULE__)
    |> Keyword.get(:penalizing_score, @penalizing_score)
  end
end
