defmodule SszTypes.SyncCommittee do
  @moduledoc """
  Struct definition for `SyncCommittee`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :pubkeys,
    :aggregate_pubkey
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          pubkeys: list(SszTypes.bls_pubkey()),
          aggregate_pubkey: SszTypes.bls_pubkey()
        }
end
