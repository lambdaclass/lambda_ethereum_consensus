defmodule Types.PendingConsolidation do
  @moduledoc """
  Struct definition for `PendingConsolidation`.
  Added in Electra fork (EIP7251).
  """

  use LambdaEthereumConsensus.Container

  @enforce_keys [:source_index, :target_index]
  defstruct [:source_index, :target_index]

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
