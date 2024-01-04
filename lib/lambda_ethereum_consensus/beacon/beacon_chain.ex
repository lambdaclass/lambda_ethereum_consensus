defmodule LambdaEthereumConsensus.Beacon.BeaconChain do
  @moduledoc false

  use GenServer

  alias LambdaEthereumConsensus.ForkChoice
  alias Types.BeaconState

  defmodule BeaconChainState do
    @moduledoc false

    defstruct [
      :genesis_time,
      :time
    ]

    @type t :: %__MODULE__{
      genesis_time: Types.uint64(),
      time: Types.uint64()
    }
  end

  @spec start_link({BeaconState.t(), Types.uint64()}) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_current_slot() :: integer()
  def get_current_slot do
    GenServer.call(__MODULE__, {:get_current_slot})
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init({BeaconState.t(), Types.uint64()}) :: {:ok, BeaconChainState.t() } | {:stop, any}
  def init({anchor_state = %BeaconState{}, time}) do
    schedule_next_tick()
    {:ok, %BeaconChainState{
      genesis_time: anchor_state.genesis_time,
      time: time
    }}
  end

  @impl true
  def handle_call({:get_current_slot}, _from, state) do
    {:reply, div(state.time - state.genesis_time, ChainSpec.get("SECONDS_PER_SLOT")), state}
  end

  @impl true
  def handle_info(:on_tick, state) do
    schedule_next_tick()
    time = :os.system_time(:second) |> floor()
    ForkChoice.Store.on_tick(time)

    {:noreply, %BeaconChainState{state | time: time}}
  end

  def schedule_next_tick do
    # For millisecond precision
    time_to_next_tick = 1000 - rem(:os.system_time(:millisecond), 1000)
    Process.send_after(__MODULE__, :on_tick, time_to_next_tick)
  end
end
