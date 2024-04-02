defmodule Types.Eth1Block do
  @moduledoc """
  Struct definition for `Eth1Block`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :timestamp,
    :deposit_root,
    :deposit_count
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          timestamp: Types.uint64(),
          deposit_root: Types.root(),
          deposit_count: Types.uint64()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      timestamp: TypeAliases.uint64(),
      deposit_root: TypeAliases.root(),
      deposit_count: TypeAliases.uint64()
    ]
  end
end
