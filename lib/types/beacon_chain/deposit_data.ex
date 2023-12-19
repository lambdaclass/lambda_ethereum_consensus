defmodule Types.DepositData do
  @moduledoc """
  Struct definition for `DepositData`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

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
          signature: Types.bls_signature()
        }
end
