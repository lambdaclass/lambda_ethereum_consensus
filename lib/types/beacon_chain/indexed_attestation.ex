defmodule Types.IndexedAttestation do
  @moduledoc """
  Struct definition for `IndexedAttestation`.
  Related definitions in `native/ssz_nif/src/types/`.
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
          # max size is MAX_VALIDATORS_PER_COMMITTEE
          attesting_indices: list(Types.validator_index()),
          data: Types.AttestationData.t(),
          signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:attesting_indices,
       {:list, TypeAliases.validator_index(), ChainSpec.get("MAX_VALIDATORS_PER_COMMITTEE")}},
      {:data, Types.AttestationData},
      {:signature, TypeAliases.bls_signature()}
    ]
  end
end
