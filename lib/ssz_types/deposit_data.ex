defmodule SszTypes.DepositData do
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
          pubkey: SszTypes.bls_pubkey(),
          withdrawal_credentials: SszTypes.bytes32(),
          amount: SszTypes.gwei(),
          signature: SszTypes.bls_signature()
        }
end
