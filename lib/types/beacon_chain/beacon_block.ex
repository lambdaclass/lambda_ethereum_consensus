defmodule Types.BeaconBlock do
  @moduledoc """
  Struct definition for `BeaconBlock`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  alias Types.BeaconBlockBody

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
          slot: Types.slot(),
          proposer_index: Types.validator_index(),
          parent_root: Types.root(),
          state_root: Types.root(),
          body: BeaconBlockBody.t()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:slot, TypeAliases.slot()},
      {:proposer_index, TypeAliases.validator_index()},
      {:parent_root, TypeAliases.root()},
      {:state_root, TypeAliases.root()},
      {:body, BeaconBlockBody}
    ]
  end
end
