defmodule LambdaEthereumConsensus.P2P.Gossip.OperationsCollector do
  @moduledoc """
  Module that stores the operations received from gossipsub.
  """
  use GenServer

  alias Types.AttesterSlashing
  alias Types.BeaconBlock
  alias Types.ProposerSlashing
  alias Types.SignedBLSToExecutionChange

  @operations [:bls_to_execution_change, :attester_slashing, :proposer_slashing]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec notify_bls_to_execution_change_gossip(SignedBLSToExecutionChange.t()) :: :ok
  def notify_bls_to_execution_change_gossip(%SignedBLSToExecutionChange{} = msg) do
    GenServer.cast(__MODULE__, {:bls_to_execution_change, msg})
  end

  @spec get_bls_to_execution_changes(non_neg_integer()) :: list(SignedBLSToExecutionChange.t())
  def get_bls_to_execution_changes(count) do
    GenServer.call(__MODULE__, {:get, :bls_to_execution_change, count})
  end

  @spec notify_attester_slashing_gossip(AttesterSlashing.t()) :: :ok
  def notify_attester_slashing_gossip(%AttesterSlashing{} = msg) do
    GenServer.cast(__MODULE__, {:attester_slashing, msg})
  end

  @spec get_attester_slashings(non_neg_integer()) :: list(AttesterSlashing.t())
  def get_attester_slashings(count) do
    GenServer.call(__MODULE__, {:get, :attester_slashing, count})
  end

  @spec notify_proposer_slashing_gossip(ProposerSlashing.t()) :: :ok
  def notify_proposer_slashing_gossip(%ProposerSlashing{} = msg) do
    GenServer.cast(__MODULE__, {:proposer_slashing, msg})
  end

  @spec get_proposer_slashings(non_neg_integer()) :: list(ProposerSlashing.t())
  def get_proposer_slashings(count) do
    GenServer.call(__MODULE__, {:get, :proposer_slashing, count})
  end

  @spec notify_new_block(BeaconBlock.t()) :: :ok
  def notify_new_block(%BeaconBlock{} = block) do
    operations = %{
      bls_to_execution_changes: block.body.bls_to_execution_changes,
      attester_slashings: block.body.attester_slashings,
      proposer_slashings: block.body.proposer_slashings
    }

    GenServer.cast(__MODULE__, {:new_block, operations})
  end

  @impl GenServer
  def init(_init_arg) do
    {:ok, %{bls_to_execution_change: [], attester_slashing: [], proposer_slashing: []}}
  end

  @impl GenServer
  def handle_call({:get, operation, count}, _from, state) when operation in @operations do
    # NOTE: we don't remove these from the state, since after a block is built
    #  :new_block will be called, and already added messages will be removed
    {:reply, Map.fetch!(state, operation) |> Enum.take(count), state}
  end

  @impl GenServer
  # TODO: filter duplicates
  def handle_cast({operation, msg}, state)
      when operation in @operations do
    new_msgs = [msg | Map.fetch!(state, operation)]
    {:noreply, Map.replace!(state, operation, new_msgs)}
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

    # TODO: improve AttesterSlashing filtering
    attester_slashings =
      state.attester_slashing |> Enum.reject(&Enum.member?(operations.attester_slashings, &1))

    slashed_proposers =
      operations.proposer_slashings |> MapSet.new(& &1.signed_header_1.message.proposer_index)

    proposer_slashings =
      state.proposer_slashing
      |> Enum.reject(
        &MapSet.member?(slashed_proposers, &1.signed_header_1.message.proposer_index)
      )

    %{
      state
      | bls_to_execution_change: bls_to_execution_changes,
        attester_slashing: attester_slashings,
        proposer_slashing: proposer_slashings
    }
  end
end
