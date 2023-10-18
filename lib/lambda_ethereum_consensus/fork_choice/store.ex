defmodule LambdaEthereumConsensus.ForkChoice.Store do
  @moduledoc """
    The Store is responsible for tracking information required for the fork choice algorithm.
  """

  use GenServer
  require Logger

  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias LambdaEthereumConsensus.Store.BlockStore
  alias SszTypes.BeaconState

  defmodule Store do
    @moduledoc """
      The Store struct is used to track information required for the fork choice algorithm.
    """
    defstruct [
      :time,
      :genesis_time,
      :justified_checkpoint,
      :finalized_checkpoint,
      :unrealized_justified_checkpoint,
      :unrealized_finalized_checkpoint,
      :proposer_boost_root,
      :equivocating_indices,
      :blocks,
      :block_states,
      :checkpoint_states,
      :latest_messages,
      :unrealized_justifications
    ]

    @type t :: %Store{
            time: SszTypes.uint64(),
            genesis_time: SszTypes.uint64(),
            justified_checkpoint: SszTypes.Checkpoint.t() | nil,
            finalized_checkpoint: SszTypes.Checkpoint.t(),
            unrealized_justified_checkpoint: SszTypes.Checkpoint.t() | nil,
            unrealized_finalized_checkpoint: SszTypes.Checkpoint.t() | nil,
            proposer_boost_root: SszTypes.root() | nil,
            equivocating_indices: MapSet.t(SszTypes.validator_index()),
            blocks: %{SszTypes.root() => SszTypes.BeaconBlock.t()},
            block_states: %{SszTypes.root() => SszTypes.BeaconState.t()},
            checkpoint_states: %{SszTypes.Checkpoint.t() => SszTypes.BeaconState.t()},
            latest_messages: %{SszTypes.validator_index() => SszTypes.Checkpoint.t()},
            unrealized_justifications: %{SszTypes.root() => SszTypes.Checkpoint.t()}
          }
  end

  ##########################
  ### Public API
  ##########################

  @spec start_link([BeaconState.t()]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_finalized_checkpoint() :: {:ok, SszTypes.Checkpoint.t()}
  def get_finalized_checkpoint do
    store = get_state()
    {:ok, store.finalized_checkpoint}
  end

  @spec get_current_slot() :: integer()
  def get_current_slot do
    store = get_state()
    div(store.time - store.genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))
  end

  @spec has_block?(SszTypes.root()) :: boolean()
  def has_block?(block_root) do
    state = get_state()
    Map.has_key?(state.blocks, block_root)
  end

  @spec on_block(SszTypes.BeaconBlock.t()) :: :ok
  def on_block(block) do
    {:ok, block_root} = Ssz.hash_tree_root(block)
    GenServer.cast(__MODULE__, {:on_block, block_root, block})
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init({BeaconState.t(), Libp2p.host()}) :: {:ok, Store.t()}
  def init({initial_state = %SszTypes.BeaconState{}, host}) do
    store = %Store{
      time: DateTime.to_unix(DateTime.utc_now()),
      genesis_time: initial_state.genesis_time,
      justified_checkpoint: initial_state.current_justified_checkpoint,
      finalized_checkpoint: initial_state.finalized_checkpoint,
      unrealized_justified_checkpoint: nil,
      unrealized_finalized_checkpoint: nil,
      proposer_boost_root: nil,
      equivocating_indices: MapSet.new(),
      blocks: %{},
      block_states: %{},
      checkpoint_states: %{},
      latest_messages: %{},
      unrealized_justifications: %{}
    }

    Process.send_after(self(), {:fetch_initial_block, initial_state, host}, 0)

    {:ok, store}
  end

  @impl GenServer
  def handle_call({:get_state}, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_cast({:on_block, block_root, block}, state) do
    Logger.info("[Fork choice] Adding block #{block_root} to the store.")
    :ok = BlockStore.store_block(block)
    {:noreply, Map.put(state, :blocks, Map.put(state.blocks, block_root, block))}
  end

  @impl GenServer
  def handle_info({:fetch_initial_block, initial_state, host}, state) do
    {:ok, state_root} = Ssz.hash_tree_root(initial_state)

    # The latest_block_header.state_root was zeroed out to avoid circular dependencies
    {:ok, block_root} =
      Ssz.hash_tree_root(Map.put(initial_state.latest_block_header, :state_root, state_root))

    case BlockDownloader.request_block_by_root(block_root, host) do
      {:ok, signed_block} ->
        Logger.info("[Checkpoint sync] Initial block fetched.")
        block = signed_block.message

        block_states = Map.put(state.block_states, block_root, initial_state)
        blocks = Map.put(state.blocks, block_root, block)

        {:noreply, state |> Map.put(:block_states, block_states) |> Map.put(:blocks, blocks)}

      {:error, message} ->
        Logger.error("[Checkpoint sync] Failed to fetch initial block: #{message}")
        Process.send_after(self(), {:fetch_initial_block, initial_state}, 200)
        {:noreply, state}
    end
  end

  ##########################
  ### Private Functions
  ##########################

  @spec get_state() :: Store.t()
  defp get_state do
    GenServer.call(__MODULE__, {:get_state})
  end
end
