defmodule LambdaEthereumConsensus.StateTransition do
  @moduledoc """
  State transition logic.
  """

  alias SszTypes.{SignedBeaconBlock, BeaconState}

  def state_transition(
        %BeaconState{} = state,
        %SignedBeaconBlock{message: _block} = _signed_block,
        _validate_result
      ) do
    # TODO: implement
    state
  end
end
