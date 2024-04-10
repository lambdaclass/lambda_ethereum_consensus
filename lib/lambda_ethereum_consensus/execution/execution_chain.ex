defmodule LambdaEthereumConsensus.Execution.ExecutionChain do
  @moduledoc """
  Polls the Execution Engine for the latest Eth1 block, and
  stores the canonical Eth1 chain for block proposing.
  """
  require Logger
  use GenServer

  alias LambdaEthereumConsensus.Execution.ExecutionClient
  alias Types.DepositTree
  alias Types.DepositTreeSnapshot
  alias Types.Eth1Data
  alias Types.ExecutionPayload

  @spec start_link(Types.uint64()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_eth1_vote(Types.slot()) :: {:ok, Types.Eth1Data.t() | nil} | {:error, any}
  def get_eth1_vote(slot) do
    GenServer.call(__MODULE__, {:get_eth1_vote, slot})
  end

  @spec notify_new_block(Types.slot(), Types.Eth1Data.t(), ExecutionPayload.t()) :: :ok
  def notify_new_block(slot, eth1_data, %ExecutionPayload{} = execution_payload) do
    payload_info = Map.take(execution_payload, [:block_hash, :block_number, :timestamp])
    GenServer.cast(__MODULE__, {:new_block, slot, eth1_data, payload_info})
  end

  @impl true
  def init({genesis_time, %DepositTreeSnapshot{} = snapshot}) do
    state = %{
      # PERF: we could use some kind of ordered map for storing votes
      eth1_data_votes: %{},
      eth1_chain: [],
      genesis_time: genesis_time,
      current_eth1_data: DepositTreeSnapshot.get_eth1_data(snapshot),
      deposit_tree: DepositTree.from_snapshot(snapshot),
      last_period: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get_eth1_vote, slot}, _from, state) do
    {:reply, compute_eth1_vote(state, slot), state}
  end

  @impl true
  def handle_cast({:new_block, slot, eth1_data, payload_info}, state) do
    state
    |> prune_state(slot)
    |> update_state_with_payload(payload_info)
    |> update_state_with_vote(eth1_data, slot)
    |> then(&{:noreply, &1})
  end

  defp prune_state(%{genesis_time: genesis_time, last_period: last_period} = state, slot) do
    current_period = compute_period(slot)

    if current_period > last_period do
      new_chain = drop_old_payloads(state.eth1_chain, genesis_time, slot)
      %{state | eth1_data_votes: %{}, eth1_chain: new_chain, last_period: current_period}
    else
      state
    end
  end

  defp update_state_with_payload(%{eth1_chain: eth1_chain} = state, payload_info) do
    %{state | eth1_chain: [payload_info | eth1_chain]}
  end

  defp drop_old_payloads(eth1_chain, genesis_time, slot) do
    period_start = voting_period_start_time(slot, genesis_time)

    follow_time_distance =
      ChainSpec.get("SECONDS_PER_ETH1_BLOCK") * ChainSpec.get("ETH1_FOLLOW_DISTANCE")

    cutoff_time = period_start - follow_time_distance * 2

    Enum.take_while(eth1_chain, fn %{timestamp: timestamp} -> timestamp >= cutoff_time end)
  end

  defp update_state_with_vote(state, eth1_data, slot) do
    votes = state.eth1_data_votes

    # We append the negative slot so ties are broken by the order of appearance
    eth1_data_votes =
      Map.update(votes, eth1_data, {1, -slot}, fn {count, i} -> {count + 1, i} end)

    new_state = %{state | eth1_data_votes: eth1_data_votes}

    if (eth1_data_votes |> Map.fetch!(eth1_data) |> elem(0)) * 2 > slots_per_eth1_voting_period() do
      update_deposit_tree(new_state, eth1_data)
    else
      new_state
    end
  end

  defp update_deposit_tree(state, %{block_hash: new_block} = eth1_data) do
    old_eth1_data = state.current_eth1_data
    old_block = old_eth1_data.block_hash

    with {:ok, %{block_number: start_block}} <- ExecutionClient.get_block_metadata(old_block),
         {:ok, %{block_number: end_block}} <- ExecutionClient.get_block_metadata(new_block),
         {:ok, deposits} <- ExecutionClient.get_deposit_logs(start_block..end_block) do
      # TODO: check if the result should be sorted by index
      deposit_tree = DepositTree.finalize(state.deposit_tree, old_eth1_data, start_block)
      new_tree = Enum.reduce(deposits, deposit_tree, &DepositTree.push_leaf(&2, &1))
      %{state | deposit_tree: new_tree, current_eth1_data: eth1_data}
    end
  end

  defp compute_eth1_vote(%{eth1_data_votes: []}, _), do: nil
  defp compute_eth1_vote(%{eth1_chain: []}, _), do: nil

  defp compute_eth1_vote(
         %{
           eth1_chain: eth1_chain,
           eth1_data_votes: seen_votes,
           genesis_time: genesis_time,
           deposit_tree: deposit_tree
         },
         slot
       ) do
    period_start = voting_period_start_time(slot, genesis_time)
    follow_time = ChainSpec.get("SECONDS_PER_ETH1_BLOCK") * ChainSpec.get("ETH1_FOLLOW_DISTANCE")

    blocks_to_consider =
      eth1_chain
      |> Enum.filter(&candidate_block?(&1.timestamp, period_start, follow_time))
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
        get_first_valid_vote(blocks_to_consider, seen_votes, deposit_tree, new_deposits)
      end
    end
  end

  defp get_first_valid_vote(blocks_to_consider, seen_votes, deposit_tree, new_deposits) do
    grouped_deposits = Enum.group_by(new_deposits, &Map.fetch!(&1, :block_number))

    {valid_votes, _last_tree} =
      blocks_to_consider
      |> Enum.reduce({MapSet.new(), deposit_tree}, fn block, {set, tree} ->
        new_tree =
          case grouped_deposits[block.block_number] do
            nil -> tree
            deposits -> update_tree_with_deposits(tree, deposits)
          end

        data = %Eth1Data{
          deposit_root: DepositTree.get_root(new_tree),
          deposit_count: DepositTree.get_deposit_count(new_tree),
          block_hash: block.block_hash
        }

        {MapSet.put(set, data), new_tree}
      end)

    # Tiebreak by smallest distance to period start
    result =
      seen_votes
      |> Stream.filter(&MapSet.member?(valid_votes, &1))
      |> Enum.max(fn {_, count1}, {_, count2} -> count1 >= count2 end, fn -> nil end)

    case result do
      # Use the first vote if there is a tie
      nil -> {:ok, List.last(valid_votes)}
      {eth1_data, _} -> {:ok, eth1_data}
    end
  end

  defp update_tree_with_deposits(tree, []), do: tree

  defp update_tree_with_deposits(tree, [deposit | rest]) do
    DepositTree.push_leaf(tree, deposit.data) |> update_tree_with_deposits(rest)
  end

  defp candidate_block?(timestamp, period_start, follow_time) do
    # follow_time = SECONDS_PER_ETH1_BLOCK * ETH1_FOLLOW_DISTANCE
    timestamp in (period_start - follow_time * 2)..(period_start - follow_time)
  end

  defp voting_period_start_time(slot, genesis_time) do
    period_start_slot = slot - rem(slot, slots_per_eth1_voting_period())
    genesis_time + period_start_slot * ChainSpec.get("SECONDS_PER_SLOT")
  end

  defp compute_period(slot), do: slot |> div(slots_per_eth1_voting_period())

  defp slots_per_eth1_voting_period,
    do: ChainSpec.get("EPOCHS_PER_ETH1_VOTING_PERIOD") * ChainSpec.get("SLOTS_PER_EPOCH")
end
