defmodule SszTypes.BLSToExecutionChange do
  @moduledoc """
  Struct definition for `BLSToExecutionChange`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :validator_index,
    :from_bls_pubkey,
    :to_execution_address
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          validator_index: SszTypes.validator_index(),
          from_bls_pubkey: SszTypes.bls_pubkey(),
          to_execution_address: SszTypes.execution_address()
        }
end
