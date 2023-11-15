defmodule LambdaEthereumConsensus.Beacon.PendingBlocks do
  @moduledoc """
    Manages pending blocks and performs validations before adding them to the fork choice.

    The main purpose of this module is making sure that a blocks parent is already in the fork choice. If it's not, it will request it to the block downloader.
  """

  use GenServer

  require Logger
  alias LambdaEthereumConsensus.ForkChoice.Store
  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias SszTypes.SignedBeaconBlock

  @type state :: %{
          pending_blocks: %{SszTypes.root() => SignedBeaconBlock.t()},
          invalid_blocks: %{SszTypes.root() => map()},
          blocks_to_download: MapSet.t(SszTypes.root())
        }

  ##########################
  ### Public API
  ##########################

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec add_block(SignedBeaconBlock.t()) :: :ok
  def add_block(signed_block) do
    GenServer.cast(__MODULE__, {:add_block, signed_block})
  end

  @spec is_pending_block(SszTypes.root()) :: boolean()
  def is_pending_block(block_root) do
    GenServer.call(__MODULE__, {:is_pending_block, block_root})
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl true
  @spec init(any) :: {:ok, state()}
  def init(_opts) do
    schedule_blocks_processing()
    schedule_blocks_download()

    {:ok, %{pending_blocks: %{}, invalid_blocks: %{}, blocks_to_download: MapSet.new()}}
  end

  @impl true
  def handle_cast({:add_block, %SignedBeaconBlock{message: block} = signed_block}, state) do
    block_root = Ssz.hash_tree_root!(block)
    pending_blocks = Map.put(state.pending_blocks, block_root, signed_block)
    {:noreply, Map.put(state, :pending_blocks, pending_blocks)}
  end

  @impl true
  def handle_call({:is_pending_block, block_root}, _from, state) do
    {:reply, Map.has_key?(state.pending_blocks, block_root), state}
  end

  @spec handle_info(any(), state()) :: {:noreply, state()}

  @doc """
  Iterates through the pending blocks and adds them to the fork choice if their parent is already in the fork choice.
  """
  @impl true
  @spec handle_info(atom(), state()) :: {:noreply, state()}
  def handle_info(:process_blocks, state) do
    state.pending_blocks
    |> Enum.sort_by(fn {_, signed_block} -> signed_block.message.slot end)
    |> Enum.reduce(state, fn {block_root, signed_block}, state ->
      parent_root = signed_block.message.parent_root

      cond do
        # If parent is invalid, block is invalid
        state.invalid_blocks |> Map.has_key?(parent_root) ->
          state
          |> Map.update!(:pending_blocks, &Map.delete(&1, block_root))
          |> Map.update!(
            :invalid_blocks,
            &Map.put(&1, block_root, signed_block.message |> Map.take([:slot, :parent_root]))
          )

        # If parent is pending, block is pending
        state.pending_blocks |> Map.has_key?(parent_root) ->
          state

        # If already in fork choice, remove from pending
        Store.has_block?(block_root) ->
          state |> Map.update!(:pending_blocks, &Map.delete(&1, block_root))

        # If parent is not in fork choice, download parent
        not Store.has_block?(parent_root) ->
          state |> Map.update!(:blocks_to_download, &MapSet.put(&1, parent_root))

        # If all the other conditions are false, add block to fork choice
        true ->
          send_block_to_forkchoice(state, signed_block, block_root)
      end
    end)
    |> then(fn state ->
      schedule_blocks_processing()
      {:noreply, state}
    end)
  end

  @impl true
  def handle_info(:download_blocks, state) do
    downloaded_blocks =
      state.blocks_to_download
      |> Enum.to_list()
      # max 20 blocks per request
      |> Enum.take(20)
      |> BlockDownloader.request_blocks_by_root()
      |> case do
        {:ok, signed_blocks} ->
          signed_blocks

        {:error, reason} ->
          Logger.warning("Block download failed: '#{reason}'")
          []
      end

    for signed_block <- downloaded_blocks do
      add_block(signed_block)
    end

    roots_to_remove =
      downloaded_blocks |> Enum.map(&Ssz.hash_tree_root!(&1.message)) |> MapSet.new()

    schedule_blocks_download()
    {:noreply, Map.update!(state, :blocks_to_download, &MapSet.difference(&1, roots_to_remove))}
  end

  ##########################
  ### Private Functions
  ##########################

  @spec send_block_to_forkchoice(state(), SignedBeaconBlock.t(), SszTypes.root()) :: state()
  defp send_block_to_forkchoice(state, signed_block, block_root) do
    case Store.on_block(signed_block, block_root) do
      :ok ->
        state |> Map.update!(:pending_blocks, &Map.delete(&1, block_root))

      :error ->
        state
        |> Map.update!(:pending_blocks, &Map.delete(&1, block_root))
        |> Map.update!(
          :invalid_blocks,
          &Map.put(&1, block_root, signed_block.message |> Map.take([:slot, :parent_root]))
        )
    end
  end

  defp schedule_blocks_processing do
    Process.send_after(self(), :process_blocks, 3000)
  end

  def schedule_blocks_download do
    Process.send_after(self(), :download_blocks, 1000)
  end
end
