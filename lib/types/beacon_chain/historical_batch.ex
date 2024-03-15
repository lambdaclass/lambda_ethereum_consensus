defmodule Types.HistoricalBatch do
  @moduledoc """
  Struct definition for `HistoricalBatch`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :block_roots,
    :state_roots
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # size SLOTS_PER_HISTORICAL_ROOT 8192
          block_roots: list(Types.root()),
          state_roots: list(Types.root())
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:block_roots, {:vector, TypeAliases.root(), ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")}},
      {:state_roots, {:vector, TypeAliases.root(), ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")}}
    ]
  end
end
