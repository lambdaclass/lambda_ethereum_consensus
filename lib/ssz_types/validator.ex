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
          pubkey: SszTypes.bls_pubkey(),
          withdrawal_credentials: SszTypes.bytes32(),
          effective_balance: SszTypes.gwei(),
          slashed: boolean,
          activation_eligibility_epoch: SszTypes.epoch(),
          activation_epoch: SszTypes.epoch(),
          exit_epoch: SszTypes.epoch(),
          withdrawable_epoch: SszTypes.epoch()
        }
end
