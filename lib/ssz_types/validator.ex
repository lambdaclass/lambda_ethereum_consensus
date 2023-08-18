defmodule SszTypes.Validator do
  @moduledoc """
  Struct definition for `Validator`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :pubkey,
    :withdrawal_credentials,
    :effective_balance,
    :slashed,
    :activation_eligibility_epoch,
    :activation_epoch,
    :exit_epoch,
    :withdrawable_epoch
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          pubkey: SszTypes.h384(),
          withdrawal_credentials: SszTypes.h256(),
          effective_balance: SszTypes.u64(),
          slashed: boolean,
          activation_eligibility_epoch: SszTypes.u64(),
          activation_epoch: SszTypes.u64(),
          exit_epoch: SszTypes.u64(),
          withdrawable_epoch: SszTypes.u64()
        }
end
