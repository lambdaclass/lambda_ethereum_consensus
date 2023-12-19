defmodule Types.SignedAggregateAndProof do
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
          message: Types.AggregateAndProof.t(),
          signature: Types.bls_signature()
        }
end
