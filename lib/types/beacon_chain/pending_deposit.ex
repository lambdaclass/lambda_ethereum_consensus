defmodule Types.PendingDeposit do
  @moduledoc """
  Struct definition for `PendingDeposit`.
  Added in Electra fork (EIP7251).
  """

  use LambdaEthereumConsensus.Container

  fields = [:pubkey, :withdrawal_credentials, :amount, :signature, :slot]
  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          pubkey: Types.bls_pubkey(),
          withdrawal_credentials: Types.bytes32(),
          amount: Types.gwei(),
          signature: Types.bls_signature(),
          slot: Types.slot()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:pubkey, TypeAliases.bls_pubkey()},
      {:withdrawal_credentials, TypeAliases.bytes32()},
      {:amount, TypeAliases.gwei()},
      {:signature, TypeAliases.bls_signature()},
      {:slot, TypeAliases.slot()}
    ]
  end
end
