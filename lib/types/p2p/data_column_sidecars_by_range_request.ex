defmodule Types.DataColumnSidecarsByRangeRequest do
  @moduledoc """
  Struct definition for `DataColumnSidecarsByRangeRequest`.
  Spec: https://github.com/ethereum/consensus-specs/blob/dev/specs/fulu/p2p-interface.md
  """
  use LambdaEthereumConsensus.Container

  @enforce_keys [:start_slot, :count, :columns]
  defstruct [
    :start_slot,
    :count,
    :columns
  ]

  @type t :: %__MODULE__{
          start_slot: Types.slot(),
          count: Types.uint64(),
          columns: [Types.column_index()]
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      start_slot: TypeAliases.slot(),
      count: TypeAliases.uint64(),
      columns: {:list, TypeAliases.uint64(), ChainSpec.get("NUMBER_OF_COLUMNS")}
    ]
  end
end
