defmodule LambdaEthereumConsensus.Execution.Eth1Chain do
  @moduledoc """
  Polls the Execution Engine for the latest Eth1 block, and
  stores the canonical Eth1 chain for block proposing.
  """
  alias Types.ExecutionPayload
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_eth1_vote do
    GenServer.call(__MODULE__, :get_eth1_vote)
  end

  def notify_new_block(slot, eth1_data, %ExecutionPayload{} = execution_payload) do
    payload_info = Map.take(execution_payload, [:block_hash, :block_number, :timestamp])
    GenServer.cast(__MODULE__, {:new_block, slot, eth1_data, payload_info})
  end

  @impl true
  def init(genesis_time) do
    # PERF: we could use some kind of ordered map for storing votes
    {:ok, %{eth1_data_votes: Keyword.new(), eth1_chain: [], genesis_time: genesis_time}}
  end

  @impl true
  def handle_call(:get_eth1_vote, _from, state) do
    {:reply, compute_eth1_vote(state), state}
  end

  @impl true
  def handle_cast({:new_block, slot, eth1_data, payload_info}, state) do
    state
    |> update_state_with_payload(slot, payload_info)
    |> update_state_with_vote(slot, eth1_data)
    |> then(&{:noreply, &1})
  end

  defp update_state_with_payload(slot, state, payload_info) do
    %{genesis_time: genesis_time, eth1_chain: eth1_chain, last_period: last_period} = state
    current_period = compute_period(slot)
    new_eth1_chain = eth1_chain |> drop_old_blocks(genesis_time, current_period, last_period)
    %{state | eth1_chain: [payload_info | new_eth1_chain], last_period: current_period}
  end

  defp drop_old_blocks(eth1_chain, _, current_period, last_period)
       when current_period == last_period do
    eth1_chain
  end

  defp drop_old_blocks(eth1_chain, genesis_time, current_period, _) do
    period_start = voting_period_start_time(current_period, genesis_time)

    follow_time_distance =
      ChainSpec.get("SECONDS_PER_ETH1_BLOCK") * ChainSpec.get("ETH1_FOLLOW_DISTANCE")

    cutoff_time = period_start - follow_time_distance * 2

    Enum.take_while(eth1_chain, fn %{timestamp: timestamp} -> timestamp >= cutoff_time end)
  end

  defp update_state_with_vote(state, _slot, eth1_data) do
    # NOTE: votes are in order of appearance
    eth1_data_votes = Keyword.update(state.eth1_data_votes, eth1_data, 0, &(&1 + 1))
    %{state | eth1_data_votes: eth1_data_votes}
  end

  defp compute_eth1_vote(%{eth1_data_votes: []}), do: nil

  defp compute_eth1_vote(state) do
    # TODO:
    # 1. validate each of the votes against the known eth1 chain
    #   a. the eth1 data should be from a candidate block
    #   b. the deposit count should be greater than or equal to the current eth1 data's
    # 2. filter out the invalid votes
    # 3. Default vote on latest eth1 block data in the period range unless eth1 chain is not live
    state.eth1_data_votes |> Enum.max(&(elem(&1, 1) >= elem(&2, 1))) |> elem(0)
  end

  defp voting_period_start_time(period, genesis_time) do
    period_start_slot = period * slots_per_eth1_voting_period()
    genesis_time + period_start_slot * ChainSpec.get("SECONDS_PER_SLOT")
  end

  defp compute_period(slot), do: slot |> div(slots_per_eth1_voting_period())

  defp slots_per_eth1_voting_period,
    do: ChainSpec.get("EPOCHS_PER_ETH1_VOTING_PERIOD") * ChainSpec.get("SLOTS_PER_EPOCH")

  # def is_candidate_block(block: Eth1Block, period_start: uint64) -> bool:
  # return (
  #     period_start - SECONDS_PER_ETH1_BLOCK * ETH1_FOLLOW_DISTANCE * 2 <= block.timestamp <= period_start - SECONDS_PER_ETH1_BLOCK * ETH1_FOLLOW_DISTANCE
  # )
end
