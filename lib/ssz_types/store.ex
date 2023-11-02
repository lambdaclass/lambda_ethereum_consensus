defmodule SszTypes.Store do
  @moduledoc """
    The Store struct is used to track information required for the fork choice algorithm.
  """
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
    :unrealized_justifications
  ]

  @type t :: %__MODULE__{
          time: SszTypes.uint64(),
          genesis_time: SszTypes.uint64(),
          justified_checkpoint: SszTypes.Checkpoint.t() | nil,
          finalized_checkpoint: SszTypes.Checkpoint.t(),
          unrealized_justified_checkpoint: SszTypes.Checkpoint.t() | nil,
          unrealized_finalized_checkpoint: SszTypes.Checkpoint.t() | nil,
          proposer_boost_root: SszTypes.root() | nil,
          equivocating_indices: MapSet.t(SszTypes.validator_index()),
          blocks: %{SszTypes.root() => SszTypes.BeaconBlock.t()},
          block_states: %{SszTypes.root() => SszTypes.BeaconState.t()},
          checkpoint_states: %{SszTypes.Checkpoint.t() => SszTypes.BeaconState.t()},
          latest_messages: %{SszTypes.validator_index() => SszTypes.Checkpoint.t()},
          unrealized_justifications: %{SszTypes.root() => SszTypes.Checkpoint.t()}
        }

  def get_current_slot(%__MODULE__{time: time, genesis_time: genesis_time}) do
    # NOTE: this assumes GENESIS_SLOT == 0
    div(time - genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))
  end
end
