defmodule Types.DepositRequest do
  @moduledoc """
  Struct definition for `DepositRequest`.
  Added in Electra fork (EIP6110).
  """

  use LambdaEthereumConsensus.Container

  @enforce_keys [:pubkey, :withdrawal_credentials, :amount, :signature, :index]
  defstruct [:pubkey, :withdrawal_credentials, :amount, :signature, :index]

  @type t :: %__MODULE__{
          pubkey: Types.bls_pubkey(),
          withdrawal_credentials: Types.bytes32(),
          amount: Types.gwei(),
          signature: Types.bls_signature(),
          index: Types.uint64()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:pubkey, TypeAliases.bls_pubkey()},
      {:withdrawal_credentials, TypeAliases.bytes32()},
      {:amount, TypeAliases.gwei()},
      {:signature, TypeAliases.bls_signature()},
      {:index, TypeAliases.uint64()}
    ]
  end
end
