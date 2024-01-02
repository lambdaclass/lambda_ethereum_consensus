defmodule Types.SignedBeaconBlock do
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
          message: Types.BeaconBlock.t(),
          signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:message, Types.BeaconBlock},
      {:signature, {:bytes, 96}}
    ]
  end
end
