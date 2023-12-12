defmodule SszTypes.HistoricalBatch do
  @moduledoc """
  Struct definition for `HistoricalBatch`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :block_roots,
    :state_roots
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # size SLOTS_PER_HISTORICAL_ROOT 8192
          block_roots: list(SszTypes.root()),
          state_roots: list(SszTypes.root())
        }

  def schema do
    [
      {:block_roots, {:vector, {:bytes, 32}, 8192}},
      {:state_roots, {:vector, {:bytes, 32}, 8192}}
    ]
  end
end
