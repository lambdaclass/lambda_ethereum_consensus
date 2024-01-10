defmodule LambdaEthereumConsensus.Store.Blocks do
  @moduledoc false
  alias LambdaEthereumConsensus.Store.BlockStore

  use GenServer

  @ets_block_by_hash __MODULE__

  ##########################
  ### Public API
  ##########################

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def store_block(block_root, signed_block) do
    cache_block(block_root, signed_block)
    GenServer.cast(__MODULE__, {:store_block, block_root, signed_block})
  end

  def get_block(block_root), do: lookup(block_root)

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  def init(_) do
    :ets.new(@ets_block_by_hash, [:set, :public, :named_table])
    {:ok, %{}}
  end

  @impl GenServer
  def handle_cast({:store_block, block_root, signed_block}, state) do
    BlockStore.store_block(signed_block, block_root)
    # TODO: remove old blocks from cache
    {:noreply, state}
  end

  ##########################
  ### Private Functions
  ##########################

  defp lookup(block_root) do
    with nil <- :ets.lookup_element(@ets_block_by_hash, block_root, 2, nil),
         block when not is_nil(block) <- fetch_block(block_root) do
      cache_block(block_root, block)
      block
    end
  end

  defp fetch_block(block_root) do
    case BlockStore.get_block(block_root) do
      {:ok, signed_block} -> signed_block
      :not_found -> nil
      # TODO: handle this somehow?
      {:error, error} -> raise "database error #{inspect(error)}"
    end
  end

  defp cache_block(block_root, signed_block) do
    :ets.insert_new(@ets_block_by_hash, {block_root, signed_block})
  end
end
