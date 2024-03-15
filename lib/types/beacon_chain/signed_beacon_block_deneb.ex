defmodule Types.SignedBeaconBlockDeneb do
  @moduledoc """
  Struct definition for `SignedBeaconBlock`.
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
          message: Types.BeaconBlockDeneb.t(),
          signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:message, Types.BeaconBlockDeneb},
      {:signature, TypeAliases.bls_signature()}
    ]
  end
end
