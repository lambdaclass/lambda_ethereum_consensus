defmodule LambdaEthereumConsensus.Beacon.BeaconChain do
  @moduledoc false

  use GenServer

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.BeaconState
  alias Types.Checkpoint

  defmodule BeaconChainState do
    @moduledoc false

    defstruct [
      :genesis_time,
      :genesis_validators_root,
      :time,
      :cached_fork_choice
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
            cached_fork_choice: fork_choice_data()
          }
  end

  @spec start_link({BeaconState.t(), Types.uint64()}) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_current_slot() :: Types.slot()
  def get_current_slot, do: GenServer.call(__MODULE__, :get_current_slot)

  @spec update_fork_choice_cache(Types.root(), Types.slot(), Checkpoint.t(), Checkpoint.t()) ::
          :ok
  def update_fork_choice_cache(head_root, head_slot, justified, finalized) do
    GenServer.cast(
      __MODULE__,
      {:update_fork_choice_cache, head_root, head_slot, justified, finalized}
    )
  end

  @spec get_finalized_checkpoint() :: Types.Checkpoint.t()
  def get_finalized_checkpoint do
    %{finalized: finalized} = GenServer.call(__MODULE__, :get_fork_choice_cache)
    finalized
  end

  @spec get_justified_checkpoint() :: Types.Checkpoint.t()
  def get_justified_checkpoint do
    %{justified: justified} = GenServer.call(__MODULE__, :get_fork_choice_cache)
    justified
  end

  @spec get_current_epoch() :: integer()
  def get_current_epoch do
    Misc.compute_epoch_at_slot(get_current_slot())
  end

  @spec get_fork_digest() :: TypeAliases.fork_digest()
  def get_fork_digest do
    GenServer.call(__MODULE__, :get_fork_digest)
  end

  @spec get_fork_digest_for_slot(Types.slot()) :: binary()
  def get_fork_digest_for_slot(slot) do
    compute_fork_digest(slot, ChainSpec.get_genesis_validators_root())
  end

  @spec get_current_status_message() :: {:ok, Types.StatusMessage.t()} | {:error, any}
  def get_current_status_message, do: GenServer.call(__MODULE__, :get_current_status_message)

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
       cached_fork_choice: fork_choice_data
     }}
  end

  @impl true
  def handle_call(:get_current_slot, _from, state) do
    {:reply, compute_current_slot(state), state}
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
    ForkChoice.on_tick(time)

    :telemetry.execute([:sync, :store], %{slot: compute_current_slot(state)})

    {:noreply, %BeaconChainState{state | time: time}}
  end

  @impl true
  def handle_cast({:update_fork_choice_cache, head_root, head_slot, justified, finalized}, state) do
    {:noreply,
     state
     |> Map.put(:cached_fork_choice, %{
       head_root: head_root,
       head_slot: head_slot,
       justified: justified,
       finalized: finalized
     })}
  end

  def schedule_next_tick do
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
end
