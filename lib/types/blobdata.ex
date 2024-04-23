# TODO: maybe allow doing this without declaring a new struct?
defmodule Types.Blobdata do
  @moduledoc """
  BlobSidecar data optimized for usage in `on_block`.
  This is needed to run the spectests.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [:blob, :proof]
  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{blob: Types.blob(), proof: Types.kzg_proof()}

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      blob: TypeAliases.blob(),
      proof: TypeAliases.kzg_proof()
    ]
  end
end
