defmodule Types.AttestationData do
  @moduledoc """
  Struct definition for `AttestationData`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  use LambdaEthereumConsensus.Container

  fields = [
    :slot,
    :index,
    :beacon_block_root,
    :source,
    :target
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          slot: Types.slot(),
          index: Types.commitee_index(),
          beacon_block_root: Types.root(),
          source: Types.Checkpoint.t(),
          target: Types.Checkpoint.t()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:slot, TypeAliases.slot()},
      {:index, TypeAliases.commitee_index()},
      {:beacon_block_root, TypeAliases.root()},
      {:source, Types.Checkpoint},
      {:target, Types.Checkpoint}
    ]
  end
end
