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
  # Hard cap: reject new peers above this limit to prevent Libp2pPort overload.
  @max_peers 100
  # Soft target: start evicting low-value peers when above this count.
  @target_peers 80
  @max_prune_size 10
  @prune_percentage 0.10

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
  @doc "Returns the number of peers currently in the peerbook."
  def peer_count() do
    fetch_peerbook!() |> map_size()
  end

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

    peerbook = fetch_peerbook!()
    penalizing_score = penalazing_score()

    case Map.get(peerbook, peer_id) do
      nil ->
        :ok

      %{score: score} when score - penalizing_score <= 0 ->
        Logger.debug("[Peerbook] Removing peer: #{inspect(Utils.format_shorten_binary(peer_id))}")

        peerbook
        |> Map.delete(peer_id)
        |> store_peerbook()

      %{score: score} ->
        peerbook
        |> Map.update!(peer_id, fn e -> %{e | score: score - penalizing_score} end)
        |> store_peerbook()
    end
  end

  def handle_new_peer(peer_id, node_id \\ nil) do
    peerbook = fetch_peerbook!()

    Logger.debug(
      "[Peerbook] New peer connected: #{inspect(Utils.format_shorten_binary(peer_id))}"
    )

    cond do
      Map.has_key?(peerbook, peer_id) ->
        # Already known, just update node_id if we got one from discovery
        if node_id != nil and peerbook[peer_id].node_id == nil do
          Map.update!(peerbook, peer_id, fn e -> %{e | node_id: node_id} end)
          |> store_peerbook()
        end

      map_size(peerbook) >= @max_peers ->
        # Hard cap reached. Only accept if we can evict a lower-value peer.
        evict_and_add(peerbook, peer_id, node_id)

      true ->
        :telemetry.execute([:peers, :connection], %{id: peer_id}, %{result: "success"})
        entry = %{score: @initial_score, node_id: node_id, custody_group_count: nil}
        Map.put(peerbook, peer_id, entry) |> store_peerbook()
        Task.start(__MODULE__, :challenge_peer, [peer_id])
    end

    prune()
  end

  # When at max_peers, evict the lowest-scoring non-PeerDAS peer to make room.
  # PeerDAS peers (with custody_group_count set) are protected from eviction.
  defp evict_and_add(peerbook, new_peer_id, node_id) do
    # Find lowest-scoring non-PeerDAS peer
    victim =
      peerbook
      |> Enum.filter(fn {_id, %{custody_group_count: cgc}} -> cgc == nil end)
      |> Enum.min_by(fn {_id, %{score: s}} -> s end, fn -> nil end)

    case victim do
      {victim_id, _} ->
        Logger.debug(
          "[Peerbook] At max_peers (#{@max_peers}), evicting #{inspect(Utils.format_shorten_binary(victim_id))} for new peer"
        )

        :telemetry.execute([:peers, :connection], %{id: new_peer_id}, %{result: "success"})
        entry = %{score: @initial_score, node_id: node_id, custody_group_count: nil}

        peerbook
        |> Map.delete(victim_id)
        |> Map.put(new_peer_id, entry)
        |> store_peerbook()

        Task.start(__MODULE__, :challenge_peer, [new_peer_id])

      nil ->
        # All peers are PeerDAS peers — don't evict, just drop the new one
        Logger.debug("[Peerbook] At max_peers (#{@max_peers}), all PeerDAS — ignoring new peer")
    end
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
      {:ok, %{custody_group_count: cgc}} when cgc != nil ->
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

      _ ->
        :ok
    end
  end

  defp prune() do
    peerbook = fetch_peerbook!()
    len = map_size(peerbook)
    excess = len - @target_peers

    cond do
      excess > @max_prune_size ->
        # Well above target: immediately evict lowest-scoring non-PeerDAS peers.
        evict_count = min(excess, @max_prune_size)

        victims =
          peerbook
          |> Enum.filter(fn {_id, %{custody_group_count: cgc}} -> cgc == nil end)
          |> Enum.sort_by(fn {_id, %{score: s}} -> s end)
          |> Enum.take(evict_count)

        if victims != [] do
          Logger.info(
            "[Peerbook] Evicting #{length(victims)} low-score peers (#{len} total, target #{@target_peers})"
          )

          pruned = Enum.reduce(victims, peerbook, fn {id, _}, pb -> Map.delete(pb, id) end)
          store_peerbook(pruned)
        end

      excess > 0 ->
        # Slightly above target: challenge random peers (existing behavior).
        prune_size = calculate_prune_size(len)

        if prune_size > 0 do
          peerbook
          |> Enum.shuffle()
          |> Enum.take(prune_size)
          |> Enum.each(fn {peer_id, _} ->
            Task.start(__MODULE__, :challenge_peer, [peer_id])
          end)
        end

      true ->
        :ok
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
