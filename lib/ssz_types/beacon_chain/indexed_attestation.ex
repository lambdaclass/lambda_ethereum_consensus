defmodule SszTypes.IndexedAttestation do
  @moduledoc """
  Struct definition for `IndexedAttestation`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :attesting_indices,
    :data,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max size is 2048
          attesting_indices: list(SszTypes.validator_index()),
          data: SszTypes.AttestationData.t(),
          signature: SszTypes.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:attesting_indices, {:list, {:int, 64}, 2048}},
      {:data, SszTypes.AttestationData},
      {:signature, {:bytes, 96}}
    ]
  end
end
