defmodule Types.BeaconBlocksByRootRequest do
  @moduledoc """
  Struct definition for `BeaconBlocksByRootRequest`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :body
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          body: list(Types.root())
        }

  @impl LambdaEthereumConsensus.Container
  def schema, do: [body: {:list, TypeAliases.root(), ChainSpec.get("MAX_REQUEST_BLOCKS")}]
end
