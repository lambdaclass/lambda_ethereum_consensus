defmodule LambdaEthereumConsensus.Beacon.BeaconChain do
  @moduledoc false

  use GenServer

  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Validator.ValidatorManager
  alias Types.BeaconState
  alias Types.Checkpoint

  require Logger

  defmodule BeaconChainState do
    @moduledoc false

    defstruct [
      :genesis_time,
      :genesis_validators_root,
      :time,
      :cached_fork_choice,
      :synced
    ]

    @type fork_choice_data :: %{
            head_root: Types.root(),
            head_slot: Types.slot(),
            justified: Types.Checkpoint.t(),
            finalized: Types.Checkpoint.t()
          }

    @type t :: %__MODULE__{
            genesis_time: Types.uint64(),
            genesis_validators_root: Types.bytes32(),
            time: Types.uint64(),
            cached_fork_choice: fork_choice_data(),
            synced: boolean()
          }
  end

  @spec start_link({BeaconState.t(), Types.uint64()}) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_current_time() :: Types.uint64()
  def get_current_time(), do: GenServer.call(__MODULE__, :get_current_time)

  @spec update_fork_choice_cache(Types.root(), Types.slot(), Checkpoint.t(), Checkpoint.t()) ::
          :ok
  def update_fork_choice_cache(head_root, head_slot, justified, finalized) do
    GenServer.cast(
      __MODULE__,
      {:update_fork_choice_cache, head_root, head_slot, justified, finalized}
    )
  end

  @spec get_finalized_checkpoint() :: Types.Checkpoint.t()
  def get_finalized_checkpoint() do
    %{finalized: finalized} = GenServer.call(__MODULE__, :get_fork_choice_cache)
    finalized
  end

  @spec get_justified_checkpoint() :: Types.Checkpoint.t()
  def get_justified_checkpoint() do
    %{justified: justified} = GenServer.call(__MODULE__, :get_fork_choice_cache)
    justified
  end

  @spec get_fork_digest() :: Types.fork_digest()
  def get_fork_digest() do
    GenServer.call(__MODULE__, :get_fork_digest)
  end

  @spec get_fork_digest_for_slot(Types.slot()) :: binary()
  def get_fork_digest_for_slot(slot) do
    compute_fork_digest(slot, ChainSpec.get_genesis_validators_root())
  end

  @spec get_fork_version() :: Types.version()
  def get_fork_version(), do: GenServer.call(__MODULE__, :get_fork_version)

  @spec get_current_status_message() :: Types.StatusMessage.t()
  def get_current_status_message(), do: GenServer.call(__MODULE__, :get_current_status_message)

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init({Types.uint64(), Types.root(), BeaconChainState.fork_choice_data(), Types.uint64()}) ::
          {:ok, BeaconChainState.t()} | {:stop, any}
  def init({genesis_time, genesis_validators_root, fork_choice_data, time}) do
    schedule_next_tick()

    {:ok,
     %BeaconChainState{
       genesis_time: genesis_time,
       genesis_validators_root: genesis_validators_root,
       time: time,
       synced: false,
       cached_fork_choice: fork_choice_data
     }}
  end

  @impl true
  def handle_call(:get_current_time, _from, %{time: time} = state) do
    {:reply, time, state}
  end

  @impl true
  def handle_call(:get_fork_choice_cache, _, %{cached_fork_choice: cached} = state) do
    {:reply, cached, state}
  end

  @impl true
  def handle_call(:get_fork_digest, _from, state) do
    fork_digest =
      compute_current_slot(state) |> compute_fork_digest(state.genesis_validators_root)

    {:reply, fork_digest, state}
  end

  @impl true
  def handle_call(:get_fork_version, _from, state) do
    fork_version =
      compute_current_slot(state)
      |> Misc.compute_epoch_at_slot()
      |> ChainSpec.get_fork_version_for_epoch()

    {:reply, fork_version, state}
  end

  @impl true
  @spec handle_call(:get_current_status_message, any, BeaconChainState.t()) ::
          {:reply, Types.StatusMessage.t(), BeaconChainState.t()}
  def handle_call(:get_current_status_message, _from, state) do
    %{
      head_root: head_root,
      head_slot: head_slot,
      finalized: %{root: finalized_root, epoch: finalized_epoch}
    } = state.cached_fork_choice

    status_message = %Types.StatusMessage{
      fork_digest: compute_fork_digest(head_slot, state.genesis_validators_root),
      finalized_root: finalized_root,
      finalized_epoch: finalized_epoch,
      head_root: head_root,
      head_slot: head_slot
    }

    {:reply, status_message, state}
  end

  @impl true
  def handle_info(:on_tick, state) do
    schedule_next_tick()
    time = :os.system_time(:second)
    new_state = %BeaconChainState{state | time: time}

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

  @impl true
  def handle_cast({:update_fork_choice_cache, head_root, head_slot, justified, finalized}, state) do
    new_cache = %{
      head_root: head_root,
      head_slot: head_slot,
      justified: justified,
      finalized: finalized
    }

    new_state = Map.put(state, :cached_fork_choice, new_cache)

    # TODO: make this check dynamic
    if compute_current_slot(state) <= head_slot do
      {:noreply, %{new_state | synced: true}}
    else
      {:noreply, new_state}
    end
  end

  def schedule_next_tick() do
    # For millisecond precision
    time_to_next_tick = 1000 - rem(:os.system_time(:millisecond), 1000)
    Process.send_after(__MODULE__, :on_tick, time_to_next_tick)
  end

  defp compute_current_slot(state) do
    div(state.time - state.genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))
  end

  defp compute_fork_digest(slot, genesis_validators_root) do
    Misc.compute_epoch_at_slot(slot)
    |> ChainSpec.get_fork_version_for_epoch()
    |> Misc.compute_fork_digest(genesis_validators_root)
  end

  @type slot_third :: :first_third | :second_third | :last_third
  @type logical_time :: {Types.slot(), slot_third()}

  @spec compute_logical_time(BeaconChainState.t()) :: logical_time()
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
