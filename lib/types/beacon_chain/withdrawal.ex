defmodule Types.Withdrawal do
  @moduledoc """
  Struct definition for `Withdrawal`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :index,
    :validator_index,
    :address,
    :amount
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          index: Types.withdrawal_index(),
          validator_index: Types.validator_index(),
          address: Types.hash32(),
          amount: Types.gwei()
        }
end
