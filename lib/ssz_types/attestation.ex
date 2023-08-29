defmodule SszTypes.Attestation do
  @moduledoc """
  Struct definition for `AttestationMainnet`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :aggregation_bits,
    :data,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max validators per committee is 2048
          aggregation_bits: SszTypes.bitlist(),
          data: SszTypes.AttestationData.t(),
          signature: SszTypes.bls_signature()
        }
end

defmodule SszTypes.AttestationMinimal do
  @moduledoc """
  Struct definition for `AttestationMinimal`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :aggregation_bits,
    :data,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max validators per committee is 2048 (same as mainnet)
          aggregation_bits: SszTypes.bitlist(),
          data: SszTypes.AttestationData.t(),
          signature: SszTypes.bls_signature()
        }
end
