defmodule LambdaEthereumConsensus.Execution.Eth1Chain do
  @moduledoc """
  Polls the Execution Engine for the latest Eth1 block, and
  stores the canonical Eth1 chain for block proposing.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_eth1_vote do
    GenServer.call(__MODULE__, :get_eth1_vote)
  end

  def notify_new_vote(eth1_data) do
    GenServer.cast(__MODULE__, {:new_vote, eth1_data})
  end

  @impl true
  def init(_opts) do
    # PERF: we could use some kind of ordered map for storing votes
    {:ok, %{eth1_data_votes: Keyword.new()}}
  end

  @impl true
  def handle_call(:get_eth1_vote, _from, state) do
    {:reply, compute_eth1_vote(state), state}
  end

  @impl true
  def handle_cast({:new_vote, eth1_data}, state) do
    {:noreply, update_state_with_vote(state, eth1_data)}
  end

  defp update_state_with_vote(state, eth1_data) do
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

  # defp slots_per_eth1_voting_period,
  #   do: ChainSpec.get("EPOCHS_PER_ETH1_VOTING_PERIOD") * ChainSpec.get("SLOTS_PER_EPOCH")
end
