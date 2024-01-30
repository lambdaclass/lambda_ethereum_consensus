defmodule Types.HistoricalSummary do
  @moduledoc """
  Struct definition for `HistoricalSummary`.
  Related definitions in `native/ssz_nif/src/types/`.
  `HistoricalSummary` matches the components of the phase0 `HistoricalBatch`
    making the two hash_tree_root-compatible.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :block_summary_root,
    :state_summary_root
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          block_summary_root: Types.root(),
          state_summary_root: Types.root()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:block_summary_root, TypeAliases.root()},
      {:state_summary_root, TypeAliases.root()}
    ]
  end
end
