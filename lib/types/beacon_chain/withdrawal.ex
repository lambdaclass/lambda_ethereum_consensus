defmodule Types.Withdrawal do
  @moduledoc """
  Struct definition for `Withdrawal`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :index,
    :validator_index,
    :address,
    :amount
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          index: Types.withdrawal_index(),
          validator_index: Types.validator_index(),
          address: Types.execution_address(),
          amount: Types.gwei()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:index, TypeAliases.withdrawal_index()},
      {:validator_index, TypeAliases.validator_index()},
      {:address, TypeAliases.execution_address()},
      {:amount, TypeAliases.gwei()}
    ]
  end
end
