defmodule Types.IndexedAttestation do
  @moduledoc """
  Struct definition for `IndexedAttestation`.
  Related definitions in `native/ssz_nif/src/types/`.

  attesting_indices is a list of indices, each one of them spanning from 0 to the amount of
  validators in the chain - 1 (it's a global index). Only the validators that participated
  are included, so not the full committee is present in the list, and they should be sorted. This
  field is the only difference with respect to Types.Attestation.

  To verify an attestation, it needs to be converted to an indexed one (get_indexed_attestation),
  with the attesting indices sorted. The bls signature can then be used to verify for the result.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :attesting_indices,
    :data,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # [Modified in Electra:EIP7549]
          attesting_indices: list(Types.validator_index()),
          data: Types.AttestationData.t(),
          signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:attesting_indices,
       {:list, TypeAliases.validator_index(),
        ChainSpec.get("MAX_VALIDATORS_PER_COMMITTEE") * ChainSpec.get("MAX_COMMITTEES_PER_SLOT")}},
      {:data, Types.AttestationData},
      {:signature, TypeAliases.bls_signature()}
    ]
  end
end
