defmodule Types.Attestation do
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
          # MAX_VALIDATORS_PER_COMMITTEE
          aggregation_bits: Types.bitlist(),
          data: Types.AttestationData.t(),
          signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:aggregation_bits, {:bitlist, ChainSpec.get("MAX_VALIDATORS_PER_COMMITTEE")}},
      {:data, Types.AttestationData},
      {:signature, TypeAliases.bls_signature()}
    ]
  end
end
