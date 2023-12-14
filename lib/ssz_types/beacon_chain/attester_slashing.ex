defmodule SszTypes.AttesterSlashing do
  @moduledoc """
  Struct definition for `AttesterSlashing`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :attestation_1,
    :attestation_2
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          attestation_1: SszTypes.IndexedAttestation.t(),
          attestation_2: SszTypes.IndexedAttestation.t()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:attestation_1, SszTypes.IndexedAttestation},
      {:attestation_2, SszTypes.IndexedAttestation}
    ]
  end
end
