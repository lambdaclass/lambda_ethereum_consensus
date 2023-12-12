defmodule SszTypes.Eth1Data do
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
          deposit_root: SszTypes.root(),
          deposit_count: SszTypes.uint64(),
          block_hash: SszTypes.hash32()
        }

  def schema do
    [
      {:deposit_root, {:bytes, 32}},
      {:deposit_count, {:int, 64}},
      {:block_hash, {:bytes, 32}}
    ]
  end
end
