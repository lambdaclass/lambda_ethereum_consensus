defmodule SszTypes.DepositData do
  @moduledoc """
  Struct definition for `DepositData`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :pubkey,
    :withdrawal_credentials,
    :amount,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          pubkey: SszTypes.bls_pubkey(),
          withdrawal_credentials: SszTypes.bytes32(),
          amount: SszTypes.gwei(),
          # Signing over DepositMessage
          signature: SszTypes.bls_signature()
        }

  def schema do
    [
      {:pubkey, {:bytes, 48}},
      {:withdrawal_credentials, {:bytes, 32}},
      {:amount, {:int, 64}},
      {:signature, {:bytes, 96}}
    ]
  end
end
