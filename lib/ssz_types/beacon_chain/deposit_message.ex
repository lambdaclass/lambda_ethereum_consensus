defmodule SszTypes.DepositMessage do
  @moduledoc """
  Struct definition for `DepositMessage`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :pubkey,
    :withdrawal_credentials,
    :amount
  ]

  @schema [
    %{pubkey: %{type: :bytes, size: 48}},
    %{withdrawal_credentials: %{type: :bytes, size: 32}},
    %{amount: %{type: :uint, size: 64}}
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          pubkey: SszTypes.bls_pubkey(),
          withdrawal_credentials: SszTypes.bytes32(),
          amount: SszTypes.gwei()
        }
  def schema, do: @schema
end
