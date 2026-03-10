defmodule Types.DataColumnsByRootIdentifier do
  @moduledoc """
  SSZ Container for `DataColumnsByRootIdentifier` (Fulu / PeerDAS, EIP-7594).

  Used in the `data_column_sidecars_by_root` req/resp protocol to request
  multiple column sidecars for a single block. The `columns` field lists
  which column indices are requested.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :block_root,
    :columns
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          block_root: Types.root(),
          columns: list(Types.column_index())
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:block_root, TypeAliases.root()},
      {:columns, {:list, TypeAliases.column_index(), ChainSpec.get("NUMBER_OF_COLUMNS")}}
    ]
  end
end
