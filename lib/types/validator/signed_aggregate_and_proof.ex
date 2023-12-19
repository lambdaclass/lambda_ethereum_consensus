defmodule SszTypes.SignedAggregateAndProof do
  @moduledoc """
  Struct definition for `SignedAggregateAndProof`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :message,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          message: SszTypes.AggregateAndProof.t(),
          signature: SszTypes.bls_signature()
        }
end
