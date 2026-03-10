defmodule Types.DataColumnIdentifier do
  @moduledoc """
  Struct definition for `DataColumnIdentifier` (Fulu / PeerDAS, EIP-7594).
  Related definitions in `native/ssz_nif/src/types/`.

  Used in `data_column_sidecars_by_root` req/resp to identify which
  data column sidecars to request: the block root and the column index.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :block_root,
    :index
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          block_root: Types.root(),
          index: Types.column_index()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:block_root, TypeAliases.root()},
      {:index, TypeAliases.column_index()}
    ]
  end
end
