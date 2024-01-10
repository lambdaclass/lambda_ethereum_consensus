defmodule Types.BeaconBlockHeader do
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
          slot: Types.slot(),
          proposer_index: Types.validator_index(),
          parent_root: Types.root(),
          state_root: Types.root(),
          body_root: Types.root()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:slot, TypeAliases.slot()},
      {:proposer_index, TypeAliases.validator_index()},
      {:parent_root, TypeAliases.root()},
      {:state_root, TypeAliases.root()},
      {:body_root, TypeAliases.root()}
    ]
  end
end
