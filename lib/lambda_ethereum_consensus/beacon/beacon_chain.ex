defmodule LambdaEthereumConsensus.Beacon.BeaconChain do
  @moduledoc false

  use GenServer

  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.Validator.ValidatorManager

  require Logger

  @type state :: %{
          genesis_time: Types.uint64(),
          time: Types.uint64()
        }

  @spec start_link({Types.uint64(), Types.uint64()}) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_current_time() :: Types.uint64()
  def get_current_time(), do: GenServer.call(__MODULE__, :get_current_time)

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init({Types.uint64(), Types.uint64()}) ::
          {:ok, state()} | {:stop, any}
  def init({genesis_time, time}) do
    schedule_next_tick()

    {:ok,
     %{
       genesis_time: genesis_time,
       time: time
     }}
  end

  @impl true
  def handle_call(:get_current_time, _from, %{time: time} = state) do
    {:reply, time, state}
  end

  @impl true
  def handle_info(:on_tick, state) do
    schedule_next_tick()
    time = :os.system_time(:second)
    new_state = %{state | time: time}

    if time >= state.genesis_time do
      PendingBlocks.on_tick(time)
      # TODO: reduce time between ticks to account for gnosis' 5s slot time.
      old_logical_time = compute_logical_time(state)
      new_logical_time = compute_logical_time(new_state)

      if old_logical_time != new_logical_time do
        notify_subscribers(new_logical_time)
      end
    end

    {:noreply, new_state}
  end

  def schedule_next_tick() do
    # For millisecond precision
    time_to_next_tick = 1000 - rem(:os.system_time(:millisecond), 1000)
    Process.send_after(__MODULE__, :on_tick, time_to_next_tick)
  end

  @type slot_third :: :first_third | :second_third | :last_third
  @type logical_time :: {Types.slot(), slot_third()}

  @spec compute_logical_time(state()) :: logical_time()
  defp compute_logical_time(state) do
    elapsed_time = state.time - state.genesis_time

    slot_thirds = div(elapsed_time * 3, ChainSpec.get("SECONDS_PER_SLOT"))
    slot = div(slot_thirds, 3)

    slot_third =
      case rem(slot_thirds, 3) do
        0 -> :first_third
        1 -> :second_third
        2 -> :last_third
      end

    {slot, slot_third}
  end

  defp notify_subscribers(logical_time) do
    log_new_slot(logical_time)
    ValidatorManager.notify_tick(logical_time)
  end

  defp log_new_slot({slot, :first_third}) do
    :telemetry.execute([:sync, :store], %{slot: slot})
    Logger.info("[BeaconChain] Slot transition", slot: slot)
  end

  defp log_new_slot(_), do: :ok
end
