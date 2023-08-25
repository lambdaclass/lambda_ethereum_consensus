defmodule SszTypes.Deposit do
  @moduledoc """
  Struct definition for `Deposit`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :proof,
    :data
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max size is 33
          proof: list(SszTypes.bytes32()),
          data: SszTypes.DepositData.t()
        }
end
