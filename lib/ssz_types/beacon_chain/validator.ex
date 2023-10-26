defmodule SszTypes.Validator do
  @moduledoc """
  Struct definition for `Validator`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  @eth1_address_withdrawal_prefix <<0x01>>

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

  @doc """
    Check if ``validator`` has an 0x01 prefixed "eth1" withdrawal credential.
  """
  @spec has_eth1_withdrawal_credential(t()) :: boolean
  def has_eth1_withdrawal_credential(%{withdrawal_credentials: withdrawal_credentials}) do
    <<first_byte_of_withdrawal_credentials::binary-size(1), _::binary>> = withdrawal_credentials
    first_byte_of_withdrawal_credentials == @eth1_address_withdrawal_prefix
  end

  @doc """
    Check if ``validator`` is fully withdrawable.
  """
  @spec is_fully_withdrawable_validator(t(), SszTypes.gwei(), SszTypes.epoch()) ::
          boolean
  def is_fully_withdrawable_validator(
        %{withdrawable_epoch: withdrawable_epoch} = validator,
        balance,
        epoch
      ) do
    has_eth1_withdrawal_credential(validator) && withdrawable_epoch <= epoch && balance > 0
  end

  @doc """
    Check if ``validator`` is partially withdrawable.
  """
  @spec is_partially_withdrawable_validator(t(), SszTypes.gwei()) :: boolean
  def is_partially_withdrawable_validator(
        %{effective_balance: effective_balance} = validator,
        balance
      ) do
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")
    has_max_effective_balance = effective_balance == max_effective_balance
    has_excess_balance = balance > max_effective_balance
    has_eth1_withdrawal_credential(validator) && has_max_effective_balance && has_excess_balance
  end
end
