defmodule Types.DepositMessage do
  @moduledoc """
  Struct definition for `DepositMessage`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

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
  def schema do
    [
      {:pubkey, TypeAliases.bls_pubkey()},
      {:withdrawal_credentials, TypeAliases.bytes32()},
      {:amount, TypeAliases.gwei()}
    ]
  end
end
