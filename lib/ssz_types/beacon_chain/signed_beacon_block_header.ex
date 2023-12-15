defmodule SszTypes.SignedBeaconBlockHeader do
  @moduledoc """
  Struct definition for `SignedBeaconBlockHeader`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :message,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          message: SszTypes.BeaconBlockHeader.t(),
          signature: SszTypes.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:message, SszTypes.BeaconBlockHeader},
      {:signature, {:bytes, 96}}
    ]
  end
end
