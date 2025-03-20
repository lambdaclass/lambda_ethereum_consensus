defmodule Types.WithdrawalRequest do
  @moduledoc """
  Struct definition for `WithdrawalRequest`.
  Added in Electra fork (EIP7251:EIP7002).
  """

  use LambdaEthereumConsensus.Container

  @enforce_keys [:source_address, :validator_pubkey, :amount]
  defstruct [:source_address, :validator_pubkey, :amount]

  @type t :: %__MODULE__{
          source_address: Types.execution_address(),
          validator_pubkey: Types.bls_pubkey(),
          amount: Types.gwei()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:source_address, TypeAliases.execution_address()},
      {:validator_pubkey, TypeAliases.bls_pubkey()},
      {:amount, TypeAliases.gwei()}
    ]
  end
end
