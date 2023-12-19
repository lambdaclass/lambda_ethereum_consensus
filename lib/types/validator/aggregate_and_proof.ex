defmodule SszTypes.AggregateAndProof do
  @moduledoc """
  Struct definition for `AggregateAndProof`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :aggregator_index,
    :aggregate,
    :selection_proof
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          aggregator_index: SszTypes.validator_index(),
          aggregate: SszTypes.Attestation.t(),
          selection_proof: SszTypes.bls_signature()
        }
end
