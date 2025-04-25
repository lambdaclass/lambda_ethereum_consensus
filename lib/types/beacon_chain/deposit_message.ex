defmodule Types.DepositMessage do
  @moduledoc """
  Struct definition for `DepositMessage`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  alias LambdaEthereumConsensus.StateTransition.Misc
  use LambdaEthereumConsensus.Container

  fields = [
    :pubkey,
    :withdrawal_credentials,
    :amount
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          pubkey: Types.bls_pubkey(),
          withdrawal_credentials: Types.bytes32(),
          amount: Types.gwei()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:pubkey, TypeAliases.bls_pubkey()},
      {:withdrawal_credentials, TypeAliases.bytes32()},
      {:amount, TypeAliases.gwei()}
    ]
  end

  @spec valid_deposit_signature?(
          Types.bls_pubkey(),
          Types.bytes32(),
          Types.gwei(),
          Types.bls_signature()
        ) :: boolean()
  def valid_deposit_signature?(pubkey, withdrawal_credentials, amount, signature) do
    deposit_message = %__MODULE__{
      pubkey: pubkey,
      withdrawal_credentials: withdrawal_credentials,
      amount: amount
    }

    domain = Misc.compute_domain(Constants.domain_deposit())
    signing_root = Misc.compute_signing_root(deposit_message, domain)

    Bls.valid?(pubkey, signing_root, signature)
  end
end
