defmodule Types.Deposit do
  @moduledoc """
  Struct definition for `Deposit`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :proof,
    :data
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max size is 33
          proof: list(Types.bytes32()),
          data: Types.DepositData.t()
        }

  @spec get_validator_from_deposit(Types.bls_pubkey(), Types.bytes32(), Types.uint64()) ::
          Types.Validator.t()
  def get_validator_from_deposit(pubkey, withdrawal_credentials, amount) do
    far_future_epoch = Constants.far_future_epoch()

    validator = %Types.Validator{
      pubkey: pubkey,
      withdrawal_credentials: withdrawal_credentials,
      activation_eligibility_epoch: far_future_epoch,
      activation_epoch: far_future_epoch,
      exit_epoch: far_future_epoch,
      withdrawable_epoch: far_future_epoch,
      effective_balance: 0,
      slashed: false
    }

    effective_balance =
      min(
        amount - rem(amount, ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")),
        Types.Validator.get_max_effective_balance(validator)
      )

    %Types.Validator{
      validator
      | effective_balance: effective_balance
    }
  end

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:proof, {:vector, TypeAliases.bytes32(), 33}},
      {:data, Types.DepositData}
    ]
  end
end
