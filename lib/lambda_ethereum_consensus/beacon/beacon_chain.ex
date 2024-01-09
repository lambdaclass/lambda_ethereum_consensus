defmodule LambdaEthereumConsensus.Beacon.BeaconChain do
  @moduledoc false

  use GenServer

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.BeaconState

  defmodule BeaconChainState do
    @moduledoc false

    defstruct [
      :genesis_time,
      :genesis_validators_root,
      :time
    ]

    @type t :: %__MODULE__{
            genesis_time: Types.uint64(),
            genesis_validators_root: Types.bytes32(),
            time: Types.uint64()
          }
  end

  @spec start_link({BeaconState.t(), Types.uint64()}) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_current_slot() :: integer()
  def get_current_slot do
    GenServer.call(__MODULE__, :get_current_slot)
  end

  @spec get_current_epoch() :: integer()
  def get_current_epoch do
    Misc.compute_epoch_at_slot(get_current_slot())
  end

  @spec get_fork_digest() :: binary()
  def get_fork_digest do
    GenServer.call(__MODULE__, {:get_fork_digest, nil})
  end

  @spec get_fork_digest_for_slot(Types.slot()) :: binary()
  def get_fork_digest_for_slot(slot) do
    GenServer.call(__MODULE__, {:get_fork_digest, slot})
  end

  @spec get_current_status_message() :: {:ok, Types.StatusMessage.t()} | {:error, any}
  def get_current_status_message do
    # TODO: un-hardcode when get_head is optimized and/or cached
    # GenServer.call(__MODULE__, :get_current_status_message, @default_timeout)

    # hardcoded response from random peer
    {:ok,
     %Types.StatusMessage{
       fork_digest: get_fork_digest(),
       finalized_root:
         Base.decode16!("7715794499C07D9954DD223EC2C6B846D3BAB27956D093000FADC1B8219F74D4"),
       finalized_epoch: 228_168,
       head_root:
         Base.decode16!("D62A74AE0F933224133C5E6E1827A2835A1E705F0CDFEE3AD25808DDEA5572DB"),
       head_slot: 7_301_450
     }}
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init({BeaconState.t(), Types.uint64()}) :: {:ok, BeaconChainState.t()} | {:stop, any}
  def init({anchor_state = %BeaconState{}, time}) do
    schedule_next_tick()

    {:ok,
     %BeaconChainState{
       genesis_time: anchor_state.genesis_time,
       genesis_validators_root: anchor_state.genesis_validators_root,
       time: time
     }}
  end

  @impl true
  def handle_call(:get_current_slot, _from, state) do
    {:reply, compute_current_slot(state), state}
  end

  @impl true
  def handle_call({:get_fork_digest, slot}, _from, state) do
    current_fork_version =
      case slot do
        nil -> compute_current_slot(state)
        _ -> slot
      end
      |> Misc.compute_epoch_at_slot()
      |> ChainSpec.get_fork_version_for_epoch()

    fork_digest =
      Misc.compute_fork_digest(
        current_fork_version,
        state.genesis_validators_root
      )

    {:reply, fork_digest, state}
  end

  @impl true
  def handle_info(:on_tick, state) do
    schedule_next_tick()
    time = :os.system_time(:second)
    ForkChoice.on_tick(time)

    :telemetry.execute([:sync, :store], %{slot: compute_current_slot(state)})

    {:noreply, %BeaconChainState{state | time: time}}
  end

  def schedule_next_tick do
    # For millisecond precision
    time_to_next_tick = 1000 - rem(:os.system_time(:millisecond), 1000)
    Process.send_after(__MODULE__, :on_tick, time_to_next_tick)
  end

  defp compute_current_slot(state) do
    div(state.time - state.genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))
  end
end
