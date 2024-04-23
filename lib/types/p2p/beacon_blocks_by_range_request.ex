defmodule Types.BeaconBlocksByRangeRequest do
  @moduledoc """
  Struct definition for `BeaconBlocksByRangeRequest`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  @enforce_keys [:start_slot, :count]
  defstruct [
    :start_slot,
    :count,
    step: 1
  ]

  @type t :: %__MODULE__{
          start_slot: Types.slot(),
          count: Types.uint64(),
          # Deprecated, must be set to 1
          step: Types.uint64()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      start_slot: TypeAliases.slot(),
      count: TypeAliases.uint64(),
      step: TypeAliases.uint64()
    ]
  end
end
