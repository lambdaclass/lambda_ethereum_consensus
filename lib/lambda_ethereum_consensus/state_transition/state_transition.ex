defmodule LambdaEthereumConsensus.StateTransition do
  @moduledoc """
  State transition logic.
  """

  alias SszTypes.{BeaconState, SignedBeaconBlock}

  def state_transition(
        %BeaconState{} = state,
        %SignedBeaconBlock{message: _block} = _signed_block,
        _validate_result
      ) do
    # TODO: implement
    state
  end
end
