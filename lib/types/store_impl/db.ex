defmodule Types.StoreImpl.Db do
  @moduledoc """
  Store implementation that stores data in the database, uncached.
  """

  alias LambdaEthereumConsensus.Store.BlockStore
  alias LambdaEthereumConsensus.Store.StateStore

  defstruct []
  @type t() :: %__MODULE__{}

  defimpl Types.StoreImpl, for: __MODULE__ do
    ## Blocks
    def store_block(_, block_root, signed_block),
      do: BlockStore.store_block(signed_block, block_root)

    def get_block(_, block_root) do
      case BlockStore.get_block(block_root) do
        {:ok, signed_block} -> signed_block.message
        _ -> nil
      end
    end

    def get_blocks(_), do: BlockStore.stream_blocks()

    ## Block states

    def store_state(_, block_root, state), do: StateStore.store_state(state, block_root)

    def get_state(_, block_root) do
      case StateStore.get_state(block_root) do
        {:ok, state} -> state
        {:error, reason} -> raise "DB failed: #{inspect(reason)}"
        :not_found -> nil
      end
    end
  end
end
