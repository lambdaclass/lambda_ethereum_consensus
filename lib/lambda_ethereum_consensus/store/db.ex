defmodule LambdaEthereumConsensus.Store.Db do
  @moduledoc """
  Module that handles the key-value store.
  """
  require Logger
  # TODO: replace GenServer with :ets
  use GenServer

  @registered_name __MODULE__
  @actions_with_db_ref [:put, :delete, :get, :iterator]
  @actions_without_db_ref [:iterator_close, :iterator_move]
  @raw_actions_with_db_ref [:status]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @registered_name)
  end

  @spec put(binary, binary) :: :ok
  def put(key, value) do
    perform(:put, [key, value])
  end

  @spec delete(binary) :: :ok
  def delete(key) do
    perform(:delete, [key])
  end

  @spec get(binary) :: {:ok, binary} | :not_found
  def get(key) do
    perform(:get, [key])
  end

  @spec size() :: non_neg_integer()
  def size() do
    {:ok, size} = perform(:status, ["leveldb.total-bytes"])
    String.to_integer(size)
  end

  @spec iterate() :: {:ok, :eleveldb.itr_ref()} | {:error, any()}
  def iterate() do
    perform(:iterator, [[]])
  end

  @spec iterate_keys() :: {:ok, :eleveldb.itr_ref()} | {:error, any()}
  def iterate_keys() do
    perform(:iterator, [[], :keys_only])
  end

  @spec iterator_close(binary) :: :ok
  def iterator_close(iter_ref) do
    perform(:iterator_close, [iter_ref])
  end

  @spec iterator_move(binary, Atom) :: {:ok, Atom, Atom} | {:error, any()}
  def iterator_move(iter_ref, action) do
    perform(:iterator_move, [iter_ref, action])
  end

  @impl true
  def init(opts) do
    db_dir = Keyword.get(opts, :dir, get_dir())
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

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp get_dir() do
    Application.fetch_env!(:lambda_ethereum_consensus, __MODULE__)
    |> Keyword.fetch!(:dir)
  end

  defp perform(name, args) when name in @actions_with_db_ref do
    apply(Exleveldb, name, [ref() | args])
  end

  defp perform(name, args) when name in @actions_without_db_ref do
    apply(Exleveldb, name, args)
  end

  defp perform(name, args) when name in @raw_actions_with_db_ref do
    apply(:eleveldb, name, [ref() | args])
  end

  defp perform(name, args) do
    Logger.error("[Db] Failed to perform #{name} with args #{inspect(args)}")
    {:error, "unknown operation"}
  end

  defp ref() do
    GenServer.call(__MODULE__, :get_ref)
  end
end
