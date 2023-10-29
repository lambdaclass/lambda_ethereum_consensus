defmodule SszTypes.DepositData do
  @moduledoc """
  Struct definition for `DepositData`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :pubkey,
    :withdrawal_credentials,
    :amount,
    :signature
  ]

  @schema [
    %{pubkey: %{type: :bytes, size: 48}},
    %{withdrawal_credentials: %{type: :bytes, size: 32}},
    %{amount: %{type: :uint, size: 64}},
    %{signature: %{type: :bytes, size: 96}}
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          pubkey: SszTypes.bls_pubkey(),
          withdrawal_credentials: SszTypes.bytes32(),
          amount: SszTypes.gwei(),
          signature: SszTypes.bls_signature()
        }
  def schema, do: @schema
end
