defmodule Types.SyncCommitteeMessage do
  @moduledoc """
  Struct definition for `SyncCommitteeMessage`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :slot,
    :beacon_block_root,
    :validator_index,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          slot: Types.slot(),
          beacon_block_root: Types.root(),
          validator_index: Types.validator_index(),
          signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:slot, TypeAliases.slot()},
      {:beacon_block_root, TypeAliases.root()},
      {:validator_index, TypeAliases.validator_index()},
      {:signature, TypeAliases.bls_signature()}
    ]
  end
end
