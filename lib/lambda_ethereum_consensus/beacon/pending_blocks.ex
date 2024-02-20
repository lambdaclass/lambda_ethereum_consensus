defmodule LambdaEthereumConsensus.Beacon.PendingBlocks do
  @moduledoc """
    Manages pending blocks and performs validations before adding them to the fork choice.

    The main purpose of this module is making sure that a blocks parent is already in the fork choice. If it's not, it will request it to the block downloader.
  """

  use GenServer
  require Logger

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.SignedBeaconBlock

  @type block_status :: :pending | :invalid | :processing | :download | :unknown
  @type state :: %{Types.root() => {SignedBeaconBlock.t() | nil, block_status()}}

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

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl true
  @spec init(any) :: {:ok, state()}
  def init(_opts) do
    schedule_blocks_processing()
    schedule_blocks_download()

    {:ok, Map.new()}
  end

  @spec handle_cast(any(), state()) :: {:noreply, state()}

  @impl true
  def handle_cast({:add_block, %SignedBeaconBlock{message: block} = signed_block}, state) do
    block_root = Ssz.hash_tree_root!(block)

    if state |> Map.get(block_root) do
      {:noreply, state}
    else
      {:noreply, state |> Map.put(block_root, {signed_block, :pending})}
    end
  end

  @impl true
  def handle_cast({:block_processed, block_root, true}, state) do
    # Block is valid
    {:noreply, state |> Map.delete(block_root)}
  end

  @impl true
  def handle_cast({:block_processed, block_root, false}, state) do
    # Block is invalid
    {:noreply, state |> Map.put(block_root, {nil, :invalid})}
  end

  @spec handle_info(any(), state()) :: {:noreply, state()}

  @doc """
  Iterates through the pending blocks and adds them to the fork choice if their parent is already in the fork choice.
  """
  @impl true
  @spec handle_info(atom(), state()) :: {:noreply, state()}
  def handle_info(:process_blocks, state) do
    state
    |> Map.filter(fn {_, {_, s}} -> s == :pending end)
    |> Enum.map(fn {root, {block, _}} -> {root, block} end)
    |> Enum.sort_by(fn {_, signed_block} -> signed_block.message.slot end)
    |> Enum.reduce(state, fn {block_root, signed_block}, state ->
      parent_root = signed_block.message.parent_root
      parent_status = get_block_status(state, parent_root)

      cond do
        # If already processed, remove it
        Blocks.get_block(block_root) ->
          state |> Map.delete(block_root)

        # If parent is invalid, block is invalid
        parent_status == :invalid ->
          state |> Map.put(block_root, {nil, :invalid})

        # If parent isn't processed, block is pending
        parent_status in [:processing, :pending, :download] ->
          state

        # If parent is not in fork choice, download parent
        !Blocks.get_block(parent_root) ->
          state |> Map.put(parent_root, {nil, :download})

        # If all the other conditions are false, add block to fork choice
        true ->
          Logger.info("Adding block to fork choice: ", root: block_root)
          ForkChoice.on_block(signed_block, block_root)
          state |> Map.put(block_root, {signed_block, :processing})
      end
    end)
    |> then(fn state ->
      schedule_blocks_processing()
      {:noreply, state}
    end)
  end

  @impl true
  def handle_info(:download_blocks, state) do
    blocks_to_download = state |> Map.filter(fn {_, {_, s}} -> s == :download end) |> Map.keys()

    downloaded_blocks =
      blocks_to_download
      |> Enum.take(16)
      |> BlockDownloader.request_blocks_by_root()
      |> case do
        {:ok, signed_blocks} ->
          signed_blocks

        {:error, reason} ->
          Logger.debug("Block download failed: '#{reason}'")
          []
      end

    new_state =
      downloaded_blocks
      |> Enum.reduce(state, fn signed_block, state ->
        block_root = Ssz.hash_tree_root!(signed_block.message)
        state |> Map.put(block_root, {signed_block, :pending})
      end)

    schedule_blocks_download()
    {:noreply, new_state}
  end

  ##########################
  ### Private Functions
  ##########################

  @spec get_block_status(state(), Types.root()) :: block_status()
  defp get_block_status(state, block_root) do
    state |> Map.get(block_root, {nil, :unknown}) |> elem(1)
  end

  def schedule_blocks_processing do
    Process.send_after(__MODULE__, :process_blocks, 3000)
  end

  def schedule_blocks_download do
    Process.send_after(__MODULE__, :download_blocks, 1000)
  end
end
