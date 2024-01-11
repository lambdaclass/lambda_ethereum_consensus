defmodule Types.Store do
  @moduledoc """
    The Store struct is used to track information required for the fork choice algorithm.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.BeaconState
  alias Types.Checkpoint
  alias Types.SignedBeaconBlock
  alias Types.StoreImpl
  alias Types.StoreImpl.InMemory

  defstruct [
    :time,
    :genesis_time,
    :justified_checkpoint,
    :finalized_checkpoint,
    :unrealized_justified_checkpoint,
    :unrealized_finalized_checkpoint,
    :proposer_boost_root,
    :equivocating_indices,
    :blocks,
    :block_states,
    :checkpoint_states,
    :latest_messages,
    :unrealized_justifications,
    :impl
  ]

  @type t :: %__MODULE__{
          time: Types.uint64(),
          genesis_time: Types.uint64(),
          justified_checkpoint: Types.Checkpoint.t() | nil,
          finalized_checkpoint: Types.Checkpoint.t(),
          unrealized_justified_checkpoint: Types.Checkpoint.t() | nil,
          unrealized_finalized_checkpoint: Types.Checkpoint.t() | nil,
          proposer_boost_root: Types.root() | nil,
          equivocating_indices: MapSet.t(Types.validator_index()),
          checkpoint_states: %{Types.Checkpoint.t() => Types.BeaconState.t()},
          latest_messages: %{Types.validator_index() => Types.Checkpoint.t()},
          unrealized_justifications: %{Types.root() => Types.Checkpoint.t()},
          # This defines where data is stored
          impl: StoreImpl.t()
        }

  def get_current_slot(%__MODULE__{time: time, genesis_time: genesis_time}) do
    # NOTE: this assumes GENESIS_SLOT == 0
    div(time - genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))
  end

  def get_ancestor(%__MODULE__{} = store, root, slot) do
    block = get_block!(store, root)

    if block.slot > slot do
      get_ancestor(store, block.parent_root, slot)
    else
      root
    end
  end

  @doc """
  Compute the checkpoint block for epoch ``epoch`` in the chain of block ``root``
  """
  def get_checkpoint_block(%__MODULE__{} = store, root, epoch) do
    epoch_first_slot = Misc.compute_start_slot_at_epoch(epoch)
    get_ancestor(store, root, epoch_first_slot)
  end

  @spec get_forkchoice_store(BeaconState.t(), SignedBeaconBlock.t(), StoreImpl.t()) ::
          {:ok, t()} | {:error, any}
  def get_forkchoice_store(
        %BeaconState{} = anchor_state,
        %SignedBeaconBlock{message: anchor_block} = signed_block,
        impl \\ %InMemory{}
      ) do
    anchor_state_root = Ssz.hash_tree_root!(anchor_state)
    anchor_block_root = Ssz.hash_tree_root!(anchor_block)

    if anchor_block.state_root == anchor_state_root do
      anchor_epoch = Accessors.get_current_epoch(anchor_state)

      anchor_checkpoint = %Checkpoint{
        epoch: anchor_epoch,
        root: anchor_block_root
      }

      time = anchor_state.genesis_time + ChainSpec.get("SECONDS_PER_SLOT") * anchor_state.slot

      %__MODULE__{
        time: time,
        genesis_time: anchor_state.genesis_time,
        justified_checkpoint: anchor_checkpoint,
        finalized_checkpoint: anchor_checkpoint,
        unrealized_justified_checkpoint: anchor_checkpoint,
        unrealized_finalized_checkpoint: anchor_checkpoint,
        proposer_boost_root: <<0::256>>,
        equivocating_indices: MapSet.new(),
        checkpoint_states: %{anchor_checkpoint => anchor_state},
        latest_messages: %{},
        unrealized_justifications: %{anchor_block_root => anchor_checkpoint},
        impl: impl
      }
      |> store_block(anchor_block_root, signed_block)
      |> store_state(anchor_block_root, anchor_state)
      |> then(&{:ok, &1})
    else
      {:error, "Anchor block state root does not match anchor state root"}
    end
  end

  ########################
  ### Delegators
  ########################

  ## Blocks

  @spec store_block(t(), Types.root(), SignedBeaconBlock.t()) :: t()
  def store_block(%__MODULE__{impl: impl} = store, block_root, signed_block),
    do: %{store | impl: StoreImpl.store_block(impl, block_root, signed_block)}

  @spec get_block(t(), Types.root()) :: Types.BeaconBlock.t() | nil
  def get_block(%__MODULE__{impl: impl}, block_root), do: StoreImpl.get_block(impl, block_root)

  @spec get_blocks(t()) :: Enumerable.t(Types.BeaconBlock.t())
  def get_blocks(%__MODULE__{impl: impl}), do: StoreImpl.get_blocks(impl)

  ## Block states

  @spec store_state(t(), Types.root(), BeaconState.t()) :: t()
  def store_state(%__MODULE__{impl: impl} = store, block_root, state),
    do: %{store | impl: StoreImpl.store_state(impl, block_root, state)}

  @spec get_state(t(), Types.root()) :: BeaconState.t() | nil
  def get_state(%__MODULE__{impl: impl}, block_root), do: StoreImpl.get_state(impl, block_root)

  ########################
  ### Wrapper functions
  ########################

  @spec get_block!(t(), Types.root()) :: Types.BeaconBlock.t()
  def get_block!(store, block_root) do
    case get_block(store, block_root) do
      nil -> raise "Block not found: #{block_root}"
      v -> v
    end
  end

  @spec get_state!(t(), Types.root()) :: BeaconState.t()
  def get_state!(store, block_root) do
    case get_state(store, block_root) do
      nil -> raise "State not found for block #{block_root}"
      v -> v
    end
  end
end
