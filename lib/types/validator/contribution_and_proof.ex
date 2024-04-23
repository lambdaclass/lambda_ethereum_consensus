defmodule Types.ContributionAndProof do
  @moduledoc """
  Struct definition for `ContributionAndProof`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :aggregator_index,
    :contribution,
    :selection_proof
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          aggregator_index: Types.validator_index(),
          contribution: Types.SyncCommitteeContribution.t(),
          selection_proof: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:aggregator_index, TypeAliases.validator_index()},
      {:contribution, Types.SyncCommitteeContribution},
      {:selection_proof, TypeAliases.bls_signature()}
    ]
  end
end
