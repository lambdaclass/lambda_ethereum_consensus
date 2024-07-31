defmodule LambdaEthereumConsensus.Ticker do
  @moduledoc false

  use GenServer

  @tick_time 1000

  require Logger

  @spec start_link([atom()]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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
  def handle_info(:on_tick, to_tick) do
    schedule_next_tick()
    # If @tick_time becomes less than 1000, we should use :millisecond instead.
    time = :os.system_time(:second)

    # TODO: This assumes that on_tick/1 is implemented for all modules in to_tick
    # this could be later a behaviour but I'm not sure we want to maintain this ticker
    # in the long run. It's important that on_tick/1 is a very fast operation and
    # that any intensive computation is done asynchronously (e.g calling a cast).
    # We could also consider using a tasks to run on_tick/1 in parallel, but for
    # now this is enough to avoid complexity.
    Enum.each(to_tick, & &1.on_tick(time))

    {:noreply, to_tick}
  end

  def schedule_next_tick() do
    # For millisecond precision
    time_to_next_tick = @tick_time - rem(:os.system_time(:millisecond), @tick_time)
    Process.send_after(__MODULE__, :on_tick, time_to_next_tick)
  end
end
