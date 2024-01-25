defmodule Types.SignedBeaconBlockHeader do
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
          message: Types.BeaconBlockHeader.t(),
          signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:message, Types.BeaconBlockHeader},
      {:signature, TypeAliases.bls_signature()}
    ]
  end
end
