defmodule SszTypes.SignedBeaconBlock do
  @moduledoc """
  Struct definition for `SignedBeaconBlock`.
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
          message: SszTypes.BeaconBlock.t(),
          signature: SszTypes.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:message, SszTypes.BeaconBlock},
      {:signature, {:bytes, 96}}
    ]
  end
end
