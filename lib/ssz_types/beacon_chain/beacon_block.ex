defmodule SszTypes.BeaconBlock do
  @moduledoc """
  Struct definition for `BeaconBlock`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :slot,
    :proposer_index,
    :parent_root,
    :state_root,
    :body
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          slot: SszTypes.slot(),
          proposer_index: SszTypes.validator_index(),
          parent_root: SszTypes.root(),
          state_root: SszTypes.root(),
          body: SszTypes.BeaconBlockBody.t()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:slot, {:int, 64}},
      {:proposer_index, {:int, 64}},
      {:parent_root, {:bytes, 32}},
      {:state_root, {:bytes, 32}},
      {:body, SszTypes.BeaconBlockBody}
    ]
  end
end
