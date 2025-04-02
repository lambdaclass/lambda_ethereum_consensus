defmodule Types.PendingConsolidation do
  @moduledoc """
  Struct definition for `PendingConsolidation`.
  Added in Electra fork (EIP7251).
  """

  use LambdaEthereumConsensus.Container

  fields = [:source_index, :target_index]
  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          source_index: Types.validator_index(),
          target_index: Types.validator_index()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:source_index, TypeAliases.validator_index()},
      {:target_index, TypeAliases.validator_index()}
    ]
  end
end
