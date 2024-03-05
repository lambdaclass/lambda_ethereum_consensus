defmodule Types.BlobSidecarsByRootRequest do
  @moduledoc """
  Struct definition for `BlobSidecarsByRootRequest`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :body
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          body: list(Types.BlobIdentifier.t())
        }

  @impl LambdaEthereumConsensus.Container
  def schema,
    do: [body: {:list, Types.BlobIdentifier, ChainSpec.get("MAX_REQUEST_BLOB_SIDECARS")}]
end
