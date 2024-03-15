defmodule Types.BlobIdentifier do
  @moduledoc """
  Struct definition for `BlobIdentifier`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :block_root,
    :index
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          block_root: Types.root(),
          index: Types.blob_index()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:block_root, TypeAliases.root()},
      {:index, TypeAliases.blob_index()}
    ]
  end
end
