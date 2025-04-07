defmodule Types.Validator do
  @moduledoc """
  Struct definition for `Validator`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

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
          pubkey: Types.bls_pubkey(),
          withdrawal_credentials: Types.bytes32(),
          effective_balance: Types.gwei(),
          slashed: boolean(),
          activation_eligibility_epoch: Types.epoch(),
          activation_epoch: Types.epoch(),
          exit_epoch: Types.epoch(),
          withdrawable_epoch: Types.epoch()
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
  @spec fully_withdrawable_validator?(t(), Types.gwei(), Types.epoch()) ::
          boolean
  def fully_withdrawable_validator?(
        %{withdrawable_epoch: withdrawable_epoch} = validator,
        balance,
        epoch
      ) do
    has_execution_withdrawal_credential(validator) && withdrawable_epoch <= epoch && balance > 0
  end

  @doc """
    Check if ``validator`` is partially withdrawable.
  """
  @spec partially_withdrawable_validator?(t(), Types.gwei()) :: boolean
  def partially_withdrawable_validator?(
        %{effective_balance: effective_balance} = validator,
        balance
      ) do
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")
    has_max_effective_balance = effective_balance == max_effective_balance
    has_excess_balance = balance > max_effective_balance
    has_eth1_withdrawal_credential(validator) && has_max_effective_balance && has_excess_balance
  end

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:pubkey, TypeAliases.bls_pubkey()},
      {:withdrawal_credentials, TypeAliases.bytes32()},
      {:effective_balance, TypeAliases.gwei()},
      {:slashed, :bool},
      {:activation_eligibility_epoch, TypeAliases.epoch()},
      {:activation_epoch, TypeAliases.epoch()},
      {:exit_epoch, TypeAliases.epoch()},
      {:withdrawable_epoch, TypeAliases.epoch()}
    ]
  end

  @spec compounding_withdrawal_credential?(Types.bytes32()) :: boolean()
  def compounding_withdrawal_credential?(withdrawal_credentials) do
    <<first_byte::binary-size(1), _::binary>> = withdrawal_credentials
    first_byte == Constants.compounding_withdrawal_prefix()
  end

  @doc """
  Check if ``validator`` has an 0x02 prefixed "compounding" withdrawal credential.
  """
  @spec has_compounding_withdrawal_credential(t()) :: boolean()
  def has_compounding_withdrawal_credential(validator) do
    compounding_withdrawal_credential?(validator.withdrawal_credential)
  end

  @doc """
  Check if ``validator`` has a 0x01 or 0x02 prefixed withdrawal credential.
  """
  @spec has_execution_withdrawal_credential(t()) :: boolean()
  def has_execution_withdrawal_credential(validator) do
    has_compounding_withdrawal_credential(validator) || has_eth1_withdrawal_credential(validator)
  end

  @doc """
  Get max effective balance for ``validator``.
  """
  @spec get_max_effective_balance(t()) :: Types.gwei()
  def get_max_effective_balance(validator) do
    if(has_compounding_withdrawal_credential(validator)) do
      ChainSpec.get("MAX_EFFECTIVE_BALANCE_ELECTRA")
    else
      ChainSpec.get("MIN_ACTIVATION_BALANCE")
    end
  end
end
