defmodule SszTypes.SyncAggregate do
  @moduledoc """
  Struct definition for `SyncAggregate`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :sync_committee_bits,
    :sync_committee_signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          sync_committee_bits: SszTypes.bitvector(),
          sync_committee_signature: SszTypes.bls_signature()
        }
end
