defmodule Types.AggregateAndProof do
  @moduledoc """
  Struct definition for `AggregateAndProof`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :aggregator_index,
    :aggregate,
    :selection_proof
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          aggregator_index: Types.validator_index(),
          aggregate: Types.Attestation.t(),
          selection_proof: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:aggregator_index, TypeAliases.validator_index()},
      {:aggregate, Types.Attestation},
      {:selection_proof, TypeAliases.bls_signature()}
    ]
  end
end
