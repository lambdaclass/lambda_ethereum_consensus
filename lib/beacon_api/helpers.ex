defmodule BeaconApi.Helpers do
  @moduledoc """
  Helper functions for the Beacon API
  """

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Store.BlockBySlot
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.StateDb
  alias Types.BeaconState
  alias Types.SignedBeaconBlock
  alias Types.StateInfo

  import Types.Guards

  @type named_root() :: :genesis | :justified | :finalized | :head
  @type block_id() :: named_root() | :invalid_id | Types.slot() | Types.root()
  @type state_id() :: named_root() | :invalid_id | Types.slot() | Types.root()
  @type block_info() ::
          {SignedBeaconBlock.t(), execution_optimistic? :: boolean(), finalized? :: boolean()}
  @type state_info() ::
          {BeaconState.t(), execution_optimistic? :: boolean(), finalized? :: boolean()}
  @type root_info() ::
          {Types.root(), execution_optimistic? :: boolean(), finalized? :: boolean()}
  @type finality_info() ::
          {Types.Checkpoint.t(), Types.Checkpoint.t(), Types.Checkpoint.t(),
           execution_optimistic? :: boolean(), finalized? :: boolean()}

  def root_by_id(:justified) do
    justified_checkpoint = ForkChoice.get_justified_checkpoint()
    # TODO compute is_optimistic_or_invalid
    execution_optimistic = true
    {:ok, {justified_checkpoint.root, execution_optimistic, false}}
  end

  def root_by_id(:finalized) do
    finalized_checkpoint = ForkChoice.get_finalized_checkpoint()
    # TODO compute is_optimistic_or_invalid
    execution_optimistic = true
    {:ok, {finalized_checkpoint.root, execution_optimistic, true}}
  end

  def root_by_id(hex_root) when is_binary(hex_root) do
    # TODO compute is_optimistic_or_invalid() and is_finalized()
    execution_optimistic = true
    finalized = false
    {:ok, {hex_root, execution_optimistic, finalized}}
  end

  @spec block_root_by_block_id(block_id()) ::
          {:ok, root_info()} | {:error, String.t()} | :not_found | :empty_slot | :invalid_id
  def block_root_by_block_id(:head) do
    with current_status <- ForkChoice.get_current_status_message() do
      # TODO compute is_optimistic_or_invalid
      execution_optimistic = true
      {:ok, {current_status.head_root, execution_optimistic, false}}
    end
  end

  def block_root_by_block_id(:genesis), do: :not_found

  def block_root_by_block_id(:justified) do
    with justified_checkpoint <- ForkChoice.get_justified_checkpoint() do
      # TODO compute is_optimistic_or_invalid
      execution_optimistic = true
      {:ok, {justified_checkpoint.root, execution_optimistic, false}}
    end
  end

  def block_root_by_block_id(:finalized) do
    with finalized_checkpoint <- ForkChoice.get_finalized_checkpoint() do
      # TODO compute is_optimistic_or_invalid
      execution_optimistic = true
      {:ok, {finalized_checkpoint.root, execution_optimistic, true}}
    end
  end

  def block_root_by_block_id(:invalid_id), do: :invalid_id

  def block_root_by_block_id(slot) when is_integer(slot) do
    with :ok <- check_valid_slot(slot, ForkChoice.get_current_chain_slot()),
         {:ok, root} when is_root(root) <- BlockBySlot.get(slot) do
      # TODO compute is_optimistic_or_invalid() and is_finalized()
      execution_optimistic = true
      finalized = false
      {:ok, {root, execution_optimistic, finalized}}
    else
      {:ok, :empty_slot} -> :empty_slot
      other -> other
    end
  end

  @spec state_root_by_state_id(state_id()) ::
          {:ok, root_info()} | {:error, String.t()} | :not_found | :empty_slot | :invalid_id
  def state_root_by_state_id(hex_root) when is_binary(hex_root) do
    # TODO compute is_optimistic_or_invalid() and is_finalized()
    execution_optimistic = true
    finalized = false

    case StateDb.get_state_by_state_root(hex_root) do
      {:ok, _state} -> {:ok, {hex_root, execution_optimistic, finalized}}
      _ -> :not_found
    end
  end

  def state_root_by_state_id(id) do
    with {:ok, {block_root, optimistic, finalized}} <- block_root_by_block_id(id),
         {:ok, block_info} <- BlockDb.get_block_info(block_root) do
      state_root = block_info.signed_block.message.state_root
      {:ok, {state_root, optimistic, finalized}}
    end
  end

  @spec block_by_block_id(block_id()) ::
          {:ok, block_info()}
          | {:error, String.t()}
          | :not_found
          | :empty_slot
          | :invalid_id
  def block_by_block_id(block_id) do
    with {:ok, {root, optimistic, finalized}} <- block_root_by_block_id(block_id),
         {:ok, block_info} <- BlockDb.get_block_info(root) do
      {:ok, {block_info.signed_block, optimistic, finalized}}
    end
  end

  @spec state_by_state_id(state_id()) ::
          {:ok, state_info()}
          | {:error, String.t()}
          | :not_found
          | :empty_slot
          | :invalid_id
  def state_by_state_id(hex_root) when is_binary(hex_root) do
    # TODO compute is_optimistic_or_invalid() and is_finalized()
    execution_optimistic = true
    finalized = false

    case StateDb.get_state_by_state_root(hex_root) do
      {:ok, %StateInfo{beacon_state: state}} -> {:ok, {state, execution_optimistic, finalized}}
      _ -> :not_found
    end
  end

  def state_by_state_id(id) do
    with {:ok, {%{message: %{state_root: state_root}}, optimistic, finalized}} <-
           block_by_block_id(id),
         {:ok, state} <-
           StateDb.get_state_by_state_root(state_root) do
      {:ok, {state, optimistic, finalized}}
    end
  end

  @spec finality_checkpoint_by_id(state_id()) ::
          {:ok, finality_info()} | {:error, String.t()} | :not_found | :empty_slot | :invalid_id
  def finality_checkpoint_by_id(id) do
    empty_checkpoint = %Types.Checkpoint{epoch: 0, root: <<0::256>>}

    with {:ok, {state, optimistic, finalized}} <- state_by_state_id(id) do
      previous_justified_ck = Map.get(state, :previous_justified_checkpoint, empty_checkpoint)
      current_justified_ck = Map.get(state, :current_justified_checkpoint, empty_checkpoint)
      finalized_ck = Map.get(state, :finalized_checkpoint, empty_checkpoint)

      {:ok, {previous_justified_ck, current_justified_ck, finalized_ck, optimistic, finalized}}
    end
  end

  @spec get_state_root(Types.root()) :: Types.root() | nil
  def get_state_root(root) do
    with %{} = block <- Blocks.get_block(root) do
      block.state_root
    end
  end

  defp check_valid_slot(slot, current_slot) when slot < current_slot, do: :ok

  defp check_valid_slot(slot, _current_slot),
    do: {:error, "slot #{slot} cannot be greater than current slot"}
end
