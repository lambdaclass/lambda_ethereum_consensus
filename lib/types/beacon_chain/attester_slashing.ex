defmodule Types.AttesterSlashing do
  @moduledoc """
  Struct definition for `AttesterSlashing`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :attestation_1,
    :attestation_2
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          attestation_1: Types.IndexedAttestation.t(),
          attestation_2: Types.IndexedAttestation.t()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:attestation_1, Types.IndexedAttestation},
      {:attestation_2, Types.IndexedAttestation}
    ]
  end
end
