defmodule LambdaEthereumConsensus.ForkChoice.Store do
  @moduledoc """
    The Store is responsible for tracking information required for the fork choice algorithm.
  """

  use GenServer
  require Logger

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
            equivocating_indices: [SszTypes.validator_index()],
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
  def start_link([initial_state]) do
    GenServer.start_link(__MODULE__, [initial_state], name: __MODULE__)
  end

  @spec get_finalized_checkpoint() :: {:ok, SszTypes.Checkpoint.t()}
  def get_finalized_checkpoint do
    checkpoint = GenServer.call(__MODULE__, :get_finalized_checkpoint)
    {:ok, checkpoint}
  end

  @spec get_slots_since_genesis() :: integer()
  def get_slots_since_genesis do
    store = get_state()
    div(store.time - store.genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))
  end

  @spec get_current_slot() :: integer()
  def get_current_slot do
    genesis_slot = 0
    genesis_slot + get_slots_since_genesis()
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init([BeaconState.t()]) :: {:ok, Store.t()}
  def init([initial_state = %SszTypes.BeaconState{}]) do
    %BeaconState{
      genesis_time: genesis_time,
      current_justified_checkpoint: current_justified_checkpoint,
      finalized_checkpoint: finalized_checkpoint
    } = initial_state

    store = %Store{
      time: DateTime.to_unix(DateTime.utc_now()),
      genesis_time: genesis_time,
      justified_checkpoint: current_justified_checkpoint,
      finalized_checkpoint: finalized_checkpoint,
      unrealized_justified_checkpoint: nil,
      unrealized_finalized_checkpoint: nil,
      proposer_boost_root: nil,
      equivocating_indices: [],
      blocks: %{},
      block_states: %{
        Ssz.hash_tree_root(initial_state) => initial_state
      },
      checkpoint_states: %{},
      latest_messages: %{},
      unrealized_justifications: %{}
    }

    {:ok, store}
  end

  @impl GenServer
  def handle_call({:get_state}, _from, state) do
    {:reply, state, state}
  end

  ##########################
  ### Private Functions
  ##########################

  @spec get_state() :: Store.t()
  defp get_state do
    GenServer.call(__MODULE__, {:get_state})
  end
end
