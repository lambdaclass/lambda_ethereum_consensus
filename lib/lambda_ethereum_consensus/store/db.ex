defmodule LambdaEthereumConsensus.Store.Db do
  @moduledoc """
  Module that handles the key-value store.
  """
  require Logger
  # TODO: replace GenServer with :ets
  use GenServer

  @registered_name __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @registered_name)
  end

  # NOTE: We call :eleveldb directly instead of through Exleveldb because
  # Exleveldb has broken typespecs (e.g. `@type db_key :: Atom | Bitstring`
  # uses module names instead of types, and the @spec for put/3 maps
  # write_options to the val parameter). This causes ~50 cascading dialyzer
  # no_return warnings across the codebase.

  @spec put(binary, binary) :: :ok
  def put(key, value) do
    :eleveldb.put(ref(), key, value, [])
  end

  @spec delete(binary) :: :ok
  def delete(key) do
    :eleveldb.delete(ref(), key, [])
  end

  @spec get(binary) :: {:ok, binary} | :not_found
  def get(key) do
    :eleveldb.get(ref(), key, [])
  end

  @spec size() :: non_neg_integer()
  def size() do
    {:ok, size} = :eleveldb.status(ref(), "leveldb.total-bytes")
    String.to_integer(size)
  end

  @spec iterate() :: {:ok, :eleveldb.itr_ref()} | {:error, any()}
  def iterate() do
    Exleveldb.iterator(ref(), [])
  end

  @spec iterate_keys() :: {:ok, :eleveldb.itr_ref()} | {:error, any()}
  def iterate_keys() do
    Exleveldb.iterator(ref(), [], :keys_only)
  end

  @spec iterator_close(:eleveldb.itr_ref()) :: :ok
  def iterator_close(iter_ref) do
    Exleveldb.iterator_close(iter_ref)
  end

  @spec iterator_move(
          :eleveldb.itr_ref(),
          :first | :last | :next | :prefetch | :prefetch_stop | :prev | binary()
        ) ::
          {:error, :invalid_iterator | :iterator_closed}
          | {:ok, binary()}
          | {:ok, binary(), binary()}
  def iterator_move(iter_ref, action) do
    Exleveldb.iterator_move(iter_ref, action)
  end

  @impl true
  def init(opts) do
    db_dir = Keyword.get_lazy(opts, :dir, &get_dir/0)
    db_full_path = Path.expand(db_dir)
    File.mkdir_p!(db_full_path)
    {:ok, ref} = Exleveldb.open(db_full_path, create_if_missing: true)
    Logger.info("Opened database in '#{db_full_path}'")
    {:ok, %{ref: ref}}
  end

  @impl true
  def terminate(_reason, %{ref: ref}) do
    :ok = Exleveldb.close(ref)
  end

  # NOTE: LevelDB database ref usage is thread-safe
  @impl true
  def handle_call(:get_ref, _from, %{ref: ref} = state), do: {:reply, ref, state}

  defp get_dir() do
    Application.fetch_env!(:lambda_ethereum_consensus, __MODULE__)
    |> Keyword.fetch!(:dir)
  end

  defp ref() do
    GenServer.call(__MODULE__, :get_ref)
  end
end
