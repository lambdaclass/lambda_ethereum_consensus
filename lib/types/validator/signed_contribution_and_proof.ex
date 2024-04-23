defmodule Types.SignedContributionAndProof do
  @moduledoc """
  Struct definition for `SignedContributionAndProof`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :message,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          message: Types.ContributionAndProof.t(),
          signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:message, Types.ContributionAndProof},
      {:signature, TypeAliases.bls_signature()}
    ]
  end
end
