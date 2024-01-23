defmodule LambdaEthereumConsensus.Store.Blocks.DbCache do
  @moduledoc false
  alias LambdaEthereumConsensus.Store.BlockStore
  alias Types.SignedBeaconBlock

  @behaviour LambdaEthereumConsensus.Store.BlocksImpl

  defstruct []
  @type t() :: %__MODULE__{}

  use GenServer

  @ets_block_by_hash :blocks_by_hash
  @ets_ttl_data :"#{@ets_block_by_hash}_ttl_data"
  @max_blocks 512
  @batch_prune_size 32

  ##########################
  ### Public API
  ##########################

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def new, do: %__MODULE__{}

  @impl true
  @spec store_block(t(), Types.root(), SignedBeaconBlock.t()) :: t()
  def store_block(impl, block_root, signed_block) do
    cache_block(block_root, signed_block)
    GenServer.cast(__MODULE__, {:store_block, block_root, signed_block})
    impl
  end

  @impl true
  @spec get_block(t(), Types.root()) :: SignedBeaconBlock.t() | nil
  def get_block(_impl, block_root), do: lookup(block_root)

  @spec clear() :: any()
  def clear, do: :ets.delete_all_objects(@ets_block_by_hash)

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  def init(_) do
    :ets.new(@ets_ttl_data, [
      :ordered_set,
      :private,
      :named_table,
      read_concurrency: false,
      write_concurrency: false,
      decentralized_counters: false
    ])

    :ets.new(@ets_block_by_hash, [:set, :public, :named_table])
    {:ok, nil}
  end

  @impl GenServer
  def handle_cast({:store_block, block_root, signed_block}, state) do
    BlockStore.store_block(signed_block, block_root)
    handle_cast({:touch_entry, block_root}, state)
  end

  @impl GenServer
  def handle_cast({:touch_entry, block_root}, state) do
    update_ttl(block_root)
    prune_cache()
    {:noreply, state}
  end

  ##########################
  ### Private Functions
  ##########################

  defp lookup(block_root) do
    case :ets.lookup_element(@ets_block_by_hash, block_root, 2, nil) do
      nil ->
        cache_miss(block_root)

      block ->
        GenServer.cast(__MODULE__, {:touch_entry, block_root})
        block
    end
  end

  defp cache_miss(block_root) do
    case fetch_block(block_root) do
      nil -> nil
      block -> cache_block(block_root, block)
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
    :ets.insert_new(@ets_block_by_hash, {block_root, signed_block, nil})
    GenServer.cast(__MODULE__, {:touch_entry, block_root})
    signed_block
  end

  defp update_ttl(block_root) do
    delete_ttl(block_root)
    uniq = :erlang.unique_integer([:monotonic])
    :ets.insert_new(@ets_ttl_data, {uniq, block_root})
    :ets.update_element(@ets_block_by_hash, block_root, {3, uniq})
  end

  defp delete_ttl(block_root) do
    case :ets.lookup_element(@ets_block_by_hash, block_root, 3, nil) do
      nil -> nil
      uniq -> :ets.delete(@ets_ttl_data, uniq)
    end
  end

  defp prune_cache do
    to_prune = :ets.info(@ets_block_by_hash, :size) - @max_blocks

    if to_prune > 0 do
      {elems, _cont} =
        :ets.select(@ets_ttl_data, [{:_, [], [:"$_"]}], to_prune + @batch_prune_size)

      elems
      |> Enum.each(fn {uniq, root} ->
        :ets.delete(@ets_ttl_data, uniq)
        :ets.delete(@ets_block_by_hash, root)
      end)
    end
  end
end
