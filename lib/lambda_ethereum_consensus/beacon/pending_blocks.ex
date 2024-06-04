defmodule LambdaEthereumConsensus.Beacon.PendingBlocks do
  @moduledoc """
    Manages pending blocks and performs validations before adding them to the fork choice.

    The main purpose of this module is making sure that a blocks parent is already in the fork choice. If it's not, it will request it to the block downloader.
  """

  use GenServer
  require Logger

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.P2P.BlobDownloader
  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias LambdaEthereumConsensus.Store.BlobDb
  alias LambdaEthereumConsensus.Store.BlockDb.BlockInfo
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.SignedBeaconBlock

  @type block_status :: :pending | :invalid | :download | :download_blobs | :unknown
  @type block_info ::
          {SignedBeaconBlock.t(), :pending | :download_blobs}
          | {nil, :invalid | :download}
  @type state :: %{Types.root() => block_info()}

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

  @spec on_tick(Types.uint64()) :: :ok
  def on_tick(time) do
    GenServer.cast(__MODULE__, {:on_tick, time})
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl true
  @spec init(any) :: {:ok, state()}
  def init(_opts) do
    schedule_blocks_processing()
    schedule_blocks_download()
    schedule_blobs_download()

    {:ok, Map.new()}
  end

  @spec handle_cast(any(), state()) :: {:noreply, state()}

  @impl true
  def handle_cast({:add_block, %SignedBeaconBlock{message: block} = signed_block}, state) do
    block_root = Ssz.hash_tree_root!(block)

    cond do
      # If already processing or processed, ignore it
      Map.has_key?(state, block_root) or Blocks.has_block?(block_root) ->
        state

      blocks_to_missing_blobs([{block_root, signed_block}]) |> Enum.empty?() ->
        state |> Map.put(block_root, {signed_block, :pending})

      true ->
        state |> Map.put(block_root, {signed_block, :download_blobs})
    end
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_cast({:on_tick, time}, state) do
    ForkChoice.on_tick(time)
    {:noreply, state}
  end

  @doc """
  Iterates through the pending blocks and adds them to the fork choice if their parent is already in the fork choice.
  """
  @impl true
  @spec handle_info(atom(), state()) :: {:noreply, state()}
  def handle_info(:process_blocks, state) do
    schedule_blocks_processing()
    {:noreply, process_blocks(state)}
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
        state |> Map.put(block_root, {signed_block, :download_blobs})
      end)

    schedule_blocks_download()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:download_blobs, state) do
    blocks_with_blobs =
      Stream.filter(state, fn {_, {_, s}} -> s == :download_blobs end)
      |> Enum.sort_by(fn {_, {signed_block, _}} -> signed_block.message.slot end)
      |> Stream.map(fn {root, {block, _}} -> {root, block} end)
      |> Enum.take(16)

    blobs_to_download = blocks_to_missing_blobs(blocks_with_blobs)

    downloaded_blobs =
      blobs_to_download
      |> BlobDownloader.request_blobs_by_root()
      |> case do
        {:ok, blobs} ->
          blobs

        {:error, reason} ->
          Logger.debug("Blob download failed: '#{reason}'")
          []
      end

    Enum.each(downloaded_blobs, &BlobDb.store_blob/1)

    new_state =
      if length(downloaded_blobs) == length(blobs_to_download) do
        blocks_with_blobs
        |> Enum.reduce(state, fn {block_root, signed_block}, state ->
          state |> Map.put(block_root, {signed_block, :pending})
        end)
      else
        state
      end

    schedule_blobs_download()
    {:noreply, new_state}
  end

  ##########################
  ### Private Functions
  ##########################

  defp process_blocks(state) do
    state
    |> Enum.filter(fn {_, {_, s}} -> s == :pending end)
    |> Enum.map(fn {root, {block, _}} -> {root, block} end)
    |> Enum.sort_by(fn {_, signed_block} -> signed_block.message.slot end)
    |> Enum.reduce(state, fn {block_root, signed_block}, state ->
      block_info = BlockInfo.from_block(signed_block, block_root, :pending)

      parent_root = signed_block.message.parent_root
      parent_status = get_block_status(state, parent_root)

      cond do
        # If parent is invalid, block is invalid
        parent_status == :invalid ->
          state |> Map.put(block_root, {nil, :invalid})

        # If parent isn't processed, block is pending
        parent_status in [:pending, :download, :download_blobs] ->
          state

        # If parent is not in fork choice, download parent
        not Blocks.has_block?(parent_root) ->
          state |> Map.put(parent_root, {nil, :download})

        # If all the other conditions are false, add block to fork choice
        true ->
          process_block(state, block_info)
      end
    end)
  end

  defp process_block(state, block_info) do
    case ForkChoice.on_block(block_info) do
      :ok ->
        state |> Map.delete(block_info.root)

      {:error, reason} ->
        Logger.error("[PendingBlocks] Saving block as invalid #{reason}",
          slot: block_info.signed_block.message.slot,
          root: block_info.root
        )

        state |> Map.put(block_info.root, {nil, :invalid})
    end
  end

  @spec get_block_status(state(), Types.root()) :: block_status()
  defp get_block_status(state, block_root) do
    state |> Map.get(block_root, {nil, :unknown}) |> elem(1)
  end

  defp blocks_to_missing_blobs(blocks) do
    Enum.flat_map(blocks, fn {block_root,
                              %{message: %{body: %{blob_kzg_commitments: commitments}}}} ->
      Stream.with_index(commitments)
      |> Enum.filter(&blob_needs_download?(&1, block_root))
      |> Enum.map(&%Types.BlobIdentifier{block_root: block_root, index: elem(&1, 1)})
    end)
  end

  defp blob_needs_download?({commitment, index}, block_root) do
    case BlobDb.get_blob_sidecar(block_root, index) do
      {:ok, %{kzg_commitment: ^commitment}} ->
        false

      _ ->
        true
    end
  end

  def schedule_blocks_processing() do
    Process.send_after(__MODULE__, :process_blocks, 500)
  end

  def schedule_blobs_download() do
    Process.send_after(__MODULE__, :download_blobs, 500)
  end

  def schedule_blocks_download() do
    Process.send_after(__MODULE__, :download_blocks, 1000)
  end
end
