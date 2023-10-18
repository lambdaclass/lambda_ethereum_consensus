defmodule LambdaEthereumConsensus.ForkChoice.Utils do
  @moduledoc """
    Utility functions for the fork choice.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias SszTypes.BeaconBlock
  alias SszTypes.BeaconState
  alias SszTypes.Checkpoint
  alias SszTypes.Store

  @spec get_forkchoice_store(BeaconState.t(), BeaconBlock.t()) :: {:ok, Store.t()} | {:error, any}
  def get_forkchoice_store(anchor_state, anchor_block) do
    {:ok, anchor_state_root} = Ssz.hash_tree_root(anchor_state)
    {:ok, anchor_block_root} = Ssz.hash_tree_root(anchor_block)

    if anchor_block.state_root == anchor_state_root do
      anchor_epoch = Accessors.get_current_epoch(anchor_state)

      finalized_checkpoint = %Checkpoint{
        epoch: anchor_epoch,
        root: anchor_state_root
      }

      justified_checkpoint = %Checkpoint{
        epoch: anchor_epoch,
        root: anchor_state_root
      }

      time = anchor_state.genesis_time + ChainSpec.get("SECONDS_PER_SLOT") * anchor_state.slot

      {:ok,
       %Store{
         time: time,
         genesis_time: anchor_state.genesis_time,
         justified_checkpoint: justified_checkpoint,
         finalized_checkpoint: finalized_checkpoint,
         unrealized_justified_checkpoint: justified_checkpoint,
         unrealized_finalized_checkpoint: finalized_checkpoint,
         proposer_boost_root: nil,
         equivocating_indices: MapSet.new(),
         blocks: %{anchor_block_root => anchor_block},
         block_states: %{anchor_block_root => anchor_state},
         checkpoint_states: %{justified_checkpoint => anchor_state},
         latest_messages: %{},
         unrealized_justifications: %{anchor_block_root => justified_checkpoint}
       }}
    else
      {:error, "Anchor block state root does not match anchor state root"}
    end
  end
end
