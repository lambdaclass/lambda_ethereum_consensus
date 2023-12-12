defmodule SszTypes.Withdrawal do
  @moduledoc """
  Struct definition for `Withdrawal`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :index,
    :validator_index,
    :address,
    :amount
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          index: SszTypes.withdrawal_index(),
          validator_index: SszTypes.validator_index(),
          address: SszTypes.hash32(),
          amount: SszTypes.gwei()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:index, {:int, 64}},
      {:validator_index, {:int, 32}},
      {:address, {:bytes, 32}},
      {:amount, {:int, 64}}
    ]
  end
end
