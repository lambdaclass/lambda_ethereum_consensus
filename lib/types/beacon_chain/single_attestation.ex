defmodule Types.SingleAttestation do
  @moduledoc """
  Struct definition for `SingleAttestation`. Added in Electra.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  use LambdaEthereumConsensus.Container

  fields = [
    :committee_index,
    :attester_index,
    :data,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          committee_index: Types.commitee_index(),
          attester_index: Types.validator_index(),
          data: Types.AttestationData.t(),
          signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:committee_index, TypeAliases.commitee_index()},
      {:attester_index, TypeAliases.validator_index()},
      {:data, Types.AttestationData},
      {:signature, TypeAliases.bls_signature()}
    ]
  end
end
