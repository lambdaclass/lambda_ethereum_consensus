defmodule Types.PendingPartialWithdrawal do
  @moduledoc """
  Struct definition for `PendingPartialWithdrawal`.
  Added in Electra fork (EIP7251).
  """

  use LambdaEthereumConsensus.Container

  fields = [:validator_index, :amount, :withdrawable_epoch]
  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          validator_index: Types.validator_index(),
          amount: Types.gwei(),
          withdrawable_epoch: Types.epoch()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:validator_index, TypeAliases.validator_index()},
      {:amount, TypeAliases.gwei()},
      {:withdrawable_epoch, TypeAliases.epoch()}
    ]
  end
end
