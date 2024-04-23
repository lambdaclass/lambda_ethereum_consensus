defmodule Types.DepositData do
  @moduledoc """
  Struct definition for `DepositData`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :pubkey,
    :withdrawal_credentials,
    :amount,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          pubkey: Types.bls_pubkey(),
          withdrawal_credentials: Types.bytes32(),
          amount: Types.gwei(),
          # Signing over DepositMessage
          signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:pubkey, TypeAliases.bls_pubkey()},
      {:withdrawal_credentials, TypeAliases.bytes32()},
      {:amount, TypeAliases.gwei()},
      {:signature, TypeAliases.bls_signature()}
    ]
  end
end
