defmodule LambdaEthereumConsensus.Beacon.Clock do
  @moduledoc false
  # This is happening sometimes, specially after recovery, need to investigate further.
  #
  # 2024-07-12 19:23:08 ERROR 22:23:08.002 GenServer LambdaEthereumConsensus.Beacon.Clock terminating
  # 2024-07-12 19:23:08 ** (CaseClauseError) no case clause matching: -1
  # 2024-07-12 19:23:08     (lambda_ethereum_consensus 0.1.0) lib/lambda_ethereum_consensus/beacon/clock.ex:86: LambdaEthereumConsensus.Beacon.Clock.compute_logical_time/1
  # 2024-07-12 19:23:08     (lambda_ethereum_consensus 0.1.0) lib/lambda_ethereum_consensus/beacon/clock.ex:57: LambdaEthereumConsensus.Beacon.Clock.handle_info/2
  # 2024-07-12 19:23:08     (stdlib 5.2.3) gen_server.erl:1095: :gen_server.try_handle_info/3
  # 2024-07-12 19:23:08     (stdlib 5.2.3) gen_server.erl:1183: :gen_server.handle_msg/6
  # 2024-07-12 19:23:08     (stdlib 5.2.3) proc_lib.erl:241: :proc_lib.init_p_do_apply/3
  # 2024-07-12 19:23:08 Last message: :on_tick
  use GenServer

  alias LambdaEthereumConsensus.Libp2pPort
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

  # FIXME: This timeout may impact the performance of the system, but due to the syncronic nature of
  # the the block proposal upon ticks, now the Clock is blocked until the block is proposed.
  @spec get_current_time() :: Types.uint64()
  def get_current_time(), do: GenServer.call(__MODULE__, :get_current_time, 19_000)

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
      Libp2pPort.on_tick(time)
      # TODO: reduce time between ticks to account for gnosis' 5s slot time.
      old_logical_time = compute_logical_time(state)
      new_logical_time = compute_logical_time(new_state)

      if old_logical_time != new_logical_time do
        log_new_slot(new_logical_time)
        ValidatorManager.notify_tick(new_logical_time)
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

  defp log_new_slot({slot, :first_third}) do
    :telemetry.execute([:sync, :store], %{slot: slot})
    Logger.info("[Clock] Slot transition", slot: slot)
  end

  defp log_new_slot(_), do: :ok
end
