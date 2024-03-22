defmodule LambdaEthereumConsensus.P2P.Gossip.OperationsCollector do
  @moduledoc """
  Module that stores the operations received from gossipsub.
  """
  alias Types.SignedBeaconBlock
  alias Types.SignedBLSToExecutionChange

  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec notify_bls_to_execution_change_gossip(SignedBLSToExecutionChange.t()) :: :ok
  def notify_bls_to_execution_change_gossip(%SignedBLSToExecutionChange{} = msg) do
    GenServer.cast(__MODULE__, {:bls_to_execution_change, msg})
  end

  @spec notify_new_block(SignedBeaconBlock.t()) :: :ok
  def notify_new_block(%SignedBeaconBlock{} = block) do
    operations = %{bls_to_execution_changes: block.message.body.bls_to_execution_changes}
    GenServer.cast(__MODULE__, {:new_block, operations})
  end

  @impl GenServer
  def init(_init_arg) do
    {:ok, %{bls_to_execution_change: []}}
  end

  @impl GenServer
  def handle_cast({:bls_to_execution_change, msg}, state) do
    new_msgs = [msg | state.bls_to_execution_change]
    {:noreply, %{state | bls_to_execution_change: new_msgs}}
  end

  def handle_cast({:new_block, operations}, state) do
    {:noreply, filter_messages(state, operations)}
  end

  defp filter_messages(state, operations) do
    indices =
      operations.bls_to_execution_changes
      |> MapSet.new(& &1.message.validator_index)

    bls_to_execution_changes =
      state.bls_to_execution_change
      |> Enum.reject(&MapSet.member?(indices, &1.message.validator_index))

    %{state | bls_to_execution_change: bls_to_execution_changes}
  end
end
