defmodule Types.Eth1Data do
  @moduledoc """
  Struct definition for `Eth1Data`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :deposit_root,
    :deposit_count,
    :block_hash
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          deposit_root: Types.root(),
          deposit_count: Types.uint64(),
          block_hash: Types.hash32()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:deposit_root, {:bytes, 32}},
      {:deposit_count, {:int, 64}},
      {:block_hash, {:bytes, 32}}
    ]
  end
end
