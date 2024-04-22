defmodule Types.DepositTreeSnapshot do
  @moduledoc """
  Struct definition for a deposit snapshot, as defined in EIP-4881.
  """

  fields = [
    :finalized,
    :deposit_root,
    :deposit_count,
    :execution_block_hash,
    :execution_block_height
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # Max size is 33
          finalized: list(Types.hash32()),
          deposit_root: Types.hash32(),
          deposit_count: Types.uint64(),
          execution_block_hash: Types.hash32(),
          execution_block_height: Types.uint64()
        }

  def for_empty_tree(block_hash, block_height) do
    empty_root = Types.DepositTree.new() |> Types.DepositTree.get_root()

    %__MODULE__{
      finalized: [],
      deposit_root: empty_root,
      deposit_count: 0,
      execution_block_hash: block_hash,
      execution_block_height: block_height
    }
  end

  def get_eth1_data(%__MODULE__{} = snapshot) do
    %Types.Eth1Data{
      deposit_root: snapshot.deposit_root,
      deposit_count: snapshot.deposit_count,
      block_hash: snapshot.execution_block_hash
    }
  end
end
