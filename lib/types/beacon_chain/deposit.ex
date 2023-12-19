defmodule SszTypes.Deposit do
  @moduledoc """
  Struct definition for `Deposit`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :proof,
    :data
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max size is 33
          proof: list(SszTypes.bytes32()),
          data: SszTypes.DepositData.t()
        }

  @spec get_validator_from_deposit(SszTypes.bls_pubkey(), SszTypes.bytes32(), SszTypes.uint64()) ::
          SszTypes.Validator.t()
  def get_validator_from_deposit(pubkey, withdrawal_credentials, amount) do
    effective_balance =
      min(
        amount - rem(amount, ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")),
        ChainSpec.get("MAX_EFFECTIVE_BALANCE")
      )

    far_future_epoch = Constants.far_future_epoch()

    %SszTypes.Validator{
      pubkey: pubkey,
      withdrawal_credentials: withdrawal_credentials,
      activation_eligibility_epoch: far_future_epoch,
      activation_epoch: far_future_epoch,
      exit_epoch: far_future_epoch,
      withdrawable_epoch: far_future_epoch,
      effective_balance: effective_balance,
      slashed: false
    }
  end
end
