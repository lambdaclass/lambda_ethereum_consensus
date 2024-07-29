defmodule LambdaEthereumConsensus.Beacon.Ticker do
  @moduledoc false

  use GenServer

  require Logger

  @spec start_link([atom()]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec register_to_tick(atom() | [atom()]) :: :ok
  def register_to_tick(to_tick) when is_atom(to_tick), do: register_to_tick([to_tick])
  def register_to_tick(to_tick) when is_list(to_tick) do
    GenServer.cast(__MODULE__, {:register_to_tick, to_tick})
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl true
  @spec init([atom()]) :: {:ok, [atom()]} | {:stop, any}
  def init(to_tick) when is_list(to_tick) do
    schedule_next_tick()

    {:ok, to_tick}
  end

  @impl true
  def handle_cast({:register_to_tick, to_tick_additions}, to_tick) do
    new_to_tick = Enum.uniq(to_tick ++ to_tick_additions)
    {:noreply, new_to_tick}
  end

  @impl true
  def handle_info(:on_tick, to_tick) do
    schedule_next_tick()
    time = :os.system_time(:second)

    Enum.each(to_tick, & &1.on_tick(time))

    {:noreply, to_tick}
  end

  def schedule_next_tick() do
    # For millisecond precision
    time_to_next_tick = 1000 - rem(:os.system_time(:millisecond), 1000)
    Process.send_after(__MODULE__, :on_tick, time_to_next_tick)
  end
end
