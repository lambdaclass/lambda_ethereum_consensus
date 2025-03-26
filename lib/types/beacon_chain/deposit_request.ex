defmodule Types.DepositRequest do
  @moduledoc """
  Struct definition for `DepositRequest`.
  Added in Electra fork (EIP6110).
  """

  use LambdaEthereumConsensus.Container

  fields = [:pubkey, :withdrawal_credentials, :amount, :signature, :index]
  @enforce_keys fields
  defstruct fields

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
