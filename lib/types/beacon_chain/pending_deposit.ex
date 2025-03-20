defmodule Types.PendingDeposit do
  @moduledoc """
  Struct definition for `PendingDeposit`.
  Added in Electra fork (EIP7251).
  """

  use LambdaEthereumConsensus.Container

  @enforce_keys [:pubkey, :withdrawal_credentials, :amount, :signature, :slot]
  defstruct [:pubkey, :withdrawal_credentials, :amount, :signature, :slot]

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
