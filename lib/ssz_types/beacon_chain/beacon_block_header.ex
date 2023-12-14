defmodule SszTypes.BeaconBlockHeader do
  @moduledoc """
  Struct definition for `BeaconBlockHeader`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :slot,
    :proposer_index,
    :parent_root,
    :state_root,
    :body_root
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          slot: SszTypes.slot(),
          proposer_index: SszTypes.validator_index(),
          parent_root: SszTypes.root(),
          state_root: SszTypes.root(),
          body_root: SszTypes.root()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:slot, {:int, 64}},
      {:proposer_index, {:int, 64}},
      {:parent_root, {:bytes, 32}},
      {:state_root, {:bytes, 32}},
      {:body_root, {:bytes, 32}}
    ]
  end
end
