defmodule Types.Attestation do
  @moduledoc """
  Struct definition for `Attestation`.
  Related definitions in `native/ssz_nif/src/types/`.

  aggregation_bits is a bit list that has the size of a committee. Each individual bit is set if
  the validator corresponding to that bit participated in attesting.
  """
  alias LambdaEthereumConsensus.Utils.BitList

  use LambdaEthereumConsensus.Container

  fields = [
    :aggregation_bits,
    :data,
    :signature,
    :committee_bits
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # [Modified in Electra:EIP7549]
          aggregation_bits: Types.bitlist(),
          data: Types.AttestationData.t(),
          signature: Types.bls_signature(),
          # [New in Electra:EIP7549]
          committee_bits: Types.bitlist()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:aggregation_bits, {:bitlist, ChainSpec.get("MAX_VALIDATORS_PER_COMMITTEE") * ChainSpec.get("MAX_COMMITTEES_PER_SLOT")}},
      {:data, Types.AttestationData},
      {:signature, TypeAliases.bls_signature()},
      {:committee_bits, {:bitlist, ChainSpec.get("MAX_COMMITTEES_PER_SLOT")}}
    ]
  end

  def encode(%__MODULE__{} = map) do
    map
    |> Map.update!(:aggregation_bits, &BitList.to_bytes/1)
    |> Map.update!(:committee_bits, &BitList.to_bytes/1)
  end

  def decode(%__MODULE__{} = map) do
    map
    |> Map.update!(:aggregation_bits, &BitList.new/1)
    |> Map.update!(:committee_bits, &BitList.new/1)
  end
end
