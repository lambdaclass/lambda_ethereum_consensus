defmodule LambdaEthereumConsensus.Execution.ExecutionChain do
  @moduledoc """
  Polls the Execution Engine for the latest Eth1 block, and
  stores the canonical Eth1 chain for block proposing.
  """
  require Logger

  alias LambdaEthereumConsensus.Execution.ExecutionClient
  alias LambdaEthereumConsensus.Store.KvSchema
  alias LambdaEthereumConsensus.Store.StoreDb
  alias Types.Deposit
  alias Types.DepositTree
  alias Types.DepositTreeSnapshot
  alias Types.Eth1Data
  alias Types.ExecutionPayload

  use KvSchema, prefix: "execution_chain"

  @type state :: %{
          eth1_data_votes: map(),
          eth1_chain: list(map()),
          current_eth1_data: %Types.Eth1Data{},
          deposit_tree: %Types.DepositTree{},
          last_period: integer()
        }

  @impl KvSchema
  @spec encode_key(String.t()) :: {:ok, binary()} | {:error, binary()}
  def encode_key(key), do: {:ok, key}

  @impl KvSchema
  @spec decode_key(binary()) :: {:ok, String.t()} | {:error, binary()}
  def decode_key(key), do: {:ok, key}

  @impl KvSchema
  @spec encode_value(map()) :: {:ok, binary()} | {:error, binary()}
  def encode_value(state), do: {:ok, :erlang.term_to_binary(state)}

  @impl KvSchema
  @spec decode_value(binary()) :: {:ok, map()} | {:error, binary()}
  def decode_value(bin), do: {:ok, :erlang.binary_to_term(bin)}

  @spec get_eth1_vote(Types.slot()) :: {:ok, Eth1Data.t() | nil} | {:error, any}
  def get_eth1_vote(slot) do
    state = fetch_execution_state!()
    compute_eth1_vote(state, slot)
  end

  @spec get_deposit_snapshot() :: DepositTreeSnapshot.t()
  def get_deposit_snapshot() do
    state = fetch_execution_state!()
    DepositTree.get_snapshot(state.deposit_tree)
  end

  @spec get_deposits(Eth1Data.t(), Eth1Data.t(), Range.t()) ::
          {:ok, [Deposit.t()] | nil} | {:error, any}
  def get_deposits(current_eth1_data, eth1_vote, deposit_range) do
    if Range.size(deposit_range) == 0 do
      {:ok, []}
    else
      state = fetch_execution_state!()
      votes = state.eth1_data_votes

      eth1_data =
        if Map.has_key?(votes, eth1_vote) and has_majority?(votes, eth1_vote),
          do: eth1_vote,
          else: current_eth1_data

      compute_deposits(state, eth1_data, deposit_range)
    end
  end

  @spec notify_new_block(Types.slot(), Eth1Data.t(), ExecutionPayload.t()) :: :ok
  def notify_new_block(slot, eth1_data, %ExecutionPayload{} = execution_payload) do
    payload_info = Map.take(execution_payload, [:block_hash, :block_number, :timestamp])

    fetch_execution_state!()
    |> prune_state(slot)
    |> update_state_with_payload(payload_info)
    |> update_state_with_vote(eth1_data)
    |> persist_execution_state()
  end

  @doc """
    Initializes the table in the db by storing the initial state of the execution chain.
  """
  def init(%DepositTreeSnapshot{} = snapshot, eth1_votes) do
    state = %{
      # PERF: we could use some kind of ordered map for storing votes
      eth1_data_votes: %{},
      eth1_chain: [],
      current_eth1_data: DepositTreeSnapshot.get_eth1_data(snapshot),
      deposit_tree: DepositTree.from_snapshot(snapshot),
      last_period: 0
    }

    updated_state = Enum.reduce(eth1_votes, state, &update_state_with_vote(&2, &1))

    StoreDb.persist_deposits_snapshot(snapshot)

    persist_execution_state(updated_state)
  end

  defp prune_state(%{last_period: last_period} = state, slot) do
    current_period = compute_period(slot)

    if current_period > last_period do
      new_chain = drop_old_payloads(state.eth1_chain, slot)
      %{state | eth1_data_votes: %{}, eth1_chain: new_chain, last_period: current_period}
    else
      state
    end
  end

  defp update_state_with_payload(%{eth1_chain: eth1_chain} = state, payload_info) do
    %{state | eth1_chain: [payload_info | eth1_chain]}
  end

  defp drop_old_payloads(eth1_chain, slot) do
    period_start = voting_period_start_time(slot)

    follow_time_distance =
      ChainSpec.get("SECONDS_PER_ETH1_BLOCK") * ChainSpec.get("ETH1_FOLLOW_DISTANCE")

    cutoff_time = period_start - follow_time_distance * 2

    Enum.take_while(eth1_chain, fn %{timestamp: timestamp} -> timestamp >= cutoff_time end)
  end

  defp update_state_with_vote(state, eth1_data) do
    votes = state.eth1_data_votes

    # We append the negative size so ties are broken by the order of appearance
    eth1_data_votes =
      Map.update(votes, eth1_data, {1, -map_size(votes)}, fn {count, i} -> {count + 1, i} end)

    new_state = %{state | eth1_data_votes: eth1_data_votes}

    if has_majority?(eth1_data_votes, eth1_data) do
      case update_deposit_tree(new_state, eth1_data) do
        {:ok, new_tree} -> %{new_state | deposit_tree: new_tree, current_eth1_data: eth1_data}
        _ -> new_state
      end
    else
      new_state
    end
  end

  defp has_majority?(eth1_data_votes, eth1_data) do
    (eth1_data_votes |> Map.fetch!(eth1_data) |> elem(0)) * 2 > slots_per_eth1_voting_period()
  end

  defp update_deposit_tree(%{current_eth1_data: eth1_data, deposit_tree: tree}, eth1_data),
    do: {:ok, tree}

  defp update_deposit_tree(state, %{block_hash: new_block}) do
    old_eth1_data = state.current_eth1_data
    old_block = old_eth1_data.block_hash

    with {:ok, %{block_number: start_block}} <- ExecutionClient.get_block_metadata(old_block),
         {:ok, %{block_number: end_block}} <- ExecutionClient.get_block_metadata(new_block),
         {:ok, deposits} <- ExecutionClient.get_deposit_logs(start_block..end_block) do
      # TODO: check if the result should be sorted by index
      deposit_tree = DepositTree.finalize(state.deposit_tree, old_eth1_data, start_block)
      # TODO: delay persisting until it's finalized
      deposit_tree |> DepositTree.get_snapshot() |> StoreDb.persist_deposits_snapshot()
      {:ok, update_tree_with_deposits(deposit_tree, deposits)}
    end
  end

  defp compute_deposits(state, eth1_data, deposit_range) do
    with :ok <- validate_range(eth1_data, deposit_range),
         {:ok, updated_tree} <- update_deposit_tree(state, eth1_data) do
      proofs =
        Enum.map(deposit_range, fn i ->
          {:ok, deposit} = DepositTree.get_deposit(updated_tree, i)
          deposit
        end)

      {:ok, proofs}
    end
  end

  defp validate_range(%{deposit_count: count}, _..deposit_end//_) when deposit_end >= count,
    do: :ok

  defp validate_range(_, _), do: {:error, "deposit range out of bounds"}

  defp compute_eth1_vote(%{eth1_data_votes: map}, _) when map == %{}, do: {:ok, nil}
  defp compute_eth1_vote(%{eth1_chain: []}, _), do: {:ok, nil}

  defp compute_eth1_vote(
         %{
           eth1_chain: eth1_chain,
           eth1_data_votes: seen_votes,
           deposit_tree: deposit_tree,
           current_eth1_data: default
         },
         slot
       ) do
    period_start = voting_period_start_time(slot)

    blocks_to_consider =
      eth1_chain
      |> Enum.filter(&candidate_block?(&1.timestamp, period_start))
      |> Enum.reverse()

    # TODO: backfill chain
    if Enum.empty?(blocks_to_consider) do
      {:error, "no execution payloads to consider"}
    else
      {block_number_min, block_number_max} =
        blocks_to_consider
        |> Stream.map(&Map.fetch!(&1, :block_number))
        |> Enum.min_max()

      # TODO: fetch asynchronously
      with {:ok, new_deposits} <-
             ExecutionClient.get_deposit_logs(block_number_min..block_number_max) do
        get_first_valid_vote(blocks_to_consider, seen_votes, deposit_tree, new_deposits, default)
      end
    end
  end

  defp get_first_valid_vote(blocks_to_consider, seen_votes, deposit_tree, new_deposits, default) do
    Logger.debug(
      "Processing new deposits: #{inspect(new_deposits)} and get first valid vote, with default: #{inspect(default)}"
    )

    {valid_votes, last_eth1_data} =
      get_valid_votes(blocks_to_consider, deposit_tree, new_deposits, default)

    # Default vote on latest eth1 block data in the period range unless eth1 chain is not live
    default_vote = last_eth1_data || default

    # Tiebreak by smallest distance to period start seen_votes is a %{eth1_data -> {count, dist}}
    result =
      seen_votes
      |> Stream.filter(fn {eth1_data, _} -> MapSet.member?(valid_votes, eth1_data) end)
      |> Enum.max(
        fn {_, {count1, dist1}}, {_, {count2, dist2}} ->
          cond do
            count1 > count2 -> true
            count1 == count2 && dist1 > dist2 -> true
            true -> false
          end
        end,
        fn -> nil end
      )

    case result do
      nil -> {:ok, default_vote}
      {eth1_data, _} -> {:ok, eth1_data}
    end
  end

  defp get_valid_votes(blocks_to_consider, deposit_tree, new_deposits, default) do
    grouped_deposits = Enum.group_by(new_deposits, &Map.fetch!(&1, :block_number))

    blocks_to_consider
    |> Enum.reduce({MapSet.new(), deposit_tree, nil}, fn block, {set, tree, last_eth1_data} ->
      new_tree =
        case grouped_deposits[block.block_number] do
          nil -> tree
          deposits -> update_tree_with_deposits(tree, deposits)
        end

      data = get_eth1_data(block, new_tree)

      if data.deposit_count >= default.deposit_count,
        do: {MapSet.put(set, data), new_tree, data},
        else: {set, new_tree, last_eth1_data}
    end)
  end

  defp get_eth1_data(block, tree) do
    %Eth1Data{
      deposit_root: DepositTree.get_root(tree),
      deposit_count: DepositTree.get_deposit_count(tree),
      block_hash: block.block_hash
    }
  end

  defp update_tree_with_deposits(tree, []), do: tree

  defp update_tree_with_deposits(tree, [deposit | rest]) do
    DepositTree.push_leaf(tree, deposit.data) |> update_tree_with_deposits(rest)
  end

  defp candidate_block?(timestamp, period_start) do
    follow_time = ChainSpec.get("SECONDS_PER_ETH1_BLOCK") * ChainSpec.get("ETH1_FOLLOW_DISTANCE")
    timestamp + follow_time <= period_start and timestamp + follow_time * 2 >= period_start
  end

  defp voting_period_start_time(slot) do
    genesis_time = StoreDb.fetch_genesis_time!()
    period_start_slot = slot - rem(slot, slots_per_eth1_voting_period())
    genesis_time + period_start_slot * ChainSpec.get("SECONDS_PER_SLOT")
  end

  defp compute_period(slot), do: slot |> div(slots_per_eth1_voting_period())

  defp slots_per_eth1_voting_period(),
    do: ChainSpec.get("EPOCHS_PER_ETH1_VOTING_PERIOD") * ChainSpec.get("SLOTS_PER_EPOCH")

  @spec persist_execution_state(state()) :: :ok | {:error, binary()}
  defp persist_execution_state(state), do: put("", state)

  @spec fetch_execution_state() :: {:ok, state()} | {:error, binary()} | :not_found
  defp fetch_execution_state(), do: get("")

  @spec fetch_execution_state!() :: state()
  defp fetch_execution_state!() do
    {:ok, state} = fetch_execution_state()
    state
  end
end
