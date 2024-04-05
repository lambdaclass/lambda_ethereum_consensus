defmodule LambdaEthereumConsensus.Execution.ExecutionChain do
  @moduledoc """
  Polls the Execution Engine for the latest Eth1 block, and
  stores the canonical Eth1 chain for block proposing.
  """
  alias Types.ExecutionPayload
  use GenServer

  @spec start_link(Types.uint64()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_eth1_vote(Types.slot()) :: Types.Eth1Data.t() | nil
  def get_eth1_vote(slot) do
    GenServer.call(__MODULE__, {:get_eth1_vote, slot})
  end

  @spec notify_new_block(Types.slot(), Types.Eth1Data.t(), ExecutionPayload.t()) :: :ok
  def notify_new_block(slot, eth1_data, %ExecutionPayload{} = execution_payload) do
    payload_info = Map.take(execution_payload, [:block_hash, :block_number, :timestamp])
    GenServer.cast(__MODULE__, {:new_block, slot, eth1_data, payload_info})
  end

  @impl true
  def init(genesis_time) do
    state = %{
      # PERF: we could use some kind of ordered map for storing votes
      eth1_data_votes: %{},
      eth1_chain: [],
      genesis_time: genesis_time,
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

    %{state | eth1_data_votes: eth1_data_votes}
  end

  defp compute_eth1_vote(%{eth1_data_votes: []}, _), do: nil

  defp compute_eth1_vote(
         %{eth1_chain: eth1_chain, eth1_data_votes: seen_votes, genesis_time: genesis_time},
         slot
       ) do
    period_start = voting_period_start_time(slot, genesis_time)
    follow_time = ChainSpec.get("SECONDS_PER_ETH1_BLOCK") * ChainSpec.get("ETH1_FOLLOW_DISTANCE")

    # TODO: get the eth1 data (deposit_root, deposit_count) for each block
    blocks_to_consider =
      Stream.filter(eth1_chain, &candidate_block?(&1.timestamp, period_start, follow_time))
      |> Enum.map(fn %{block_hash: hash} -> hash end)

    # Tiebreak by smallest distance to period start
    result =
      seen_votes
      |> Stream.filter(fn {%{block_hash: hash}, _} -> Enum.member?(blocks_to_consider, hash) end)
      |> Enum.max(fn {_, count1}, {_, count2} -> count1 >= count2 end, fn -> nil end)

    case result do
      nil -> nil
      {eth1_data, _} -> eth1_data
    end
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
