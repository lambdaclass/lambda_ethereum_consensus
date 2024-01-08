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
      {:pubkey, {:bytes, 48}},
      {:withdrawal_credentials, {:bytes, 32}},
      {:amount, {:int, 64}}
    ]
  end
end
