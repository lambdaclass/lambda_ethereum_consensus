defmodule SszTypes.Attestation do
  @moduledoc """
  Struct definition for `AttestationMainnet`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

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

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:aggregation_bits, {:bitlist, 2048}},
      {:data, SszTypes.AttestationData},
      {:signature, {:bytes, 96}}
    ]
  end
end
