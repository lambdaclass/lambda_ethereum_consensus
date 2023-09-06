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
          # SyncCommittee size is 512
          pubkeys: list(SszTypes.bls_pubkey()),
          aggregate_pubkey: SszTypes.bls_pubkey()
        }
end

defmodule SszTypes.SyncCommitteeMinimal do
  @moduledoc """
  Struct definition for `SyncCommitteeMinimal`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :pubkeys,
    :aggregate_pubkey
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # SyncCommittee size is 32
          pubkeys: list(SszTypes.bls_pubkey()),
          aggregate_pubkey: SszTypes.bls_pubkey()
        }
end
