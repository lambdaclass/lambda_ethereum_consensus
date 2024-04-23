defmodule Types.SyncAggregatorSelectionData do
  @moduledoc """
  Struct definition for `SyncAggregatorSelectionData`.
  """
  use LambdaEthereumConsensus.Container

  fields = [:slot, :subcommittee_index]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          slot: Types.slot(),
          subcommittee_index: Types.uint64()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      slot: TypeAliases.slot(),
      subcommittee_index: TypeAliases.uint64()
    ]
  end
end
