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
  @type state :: nil

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

    {:ok, nil}
  end

  @spec handle_cast(any(), state()) :: {:noreply, state()}

  @impl true
  def handle_cast({:add_block, %SignedBeaconBlock{} = signed_block}, _state) do
    block_info = BlockInfo.from_block(signed_block)

    # If already processing or processed, ignore it
    if not Blocks.has_block?(block_info.root) do
      if Enum.empty?(missing_blobs(block_info)) do
        block_info
      else
        block_info |> BlockInfo.change_status(:download_blobs)
      end
      |> Blocks.new_block_info()
    end

    {:noreply, nil}
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
  def handle_info(:process_blocks, _state) do
    schedule_blocks_processing()
    process_blocks()
    {:noreply, nil}
  end

  @impl true
  def handle_info(:download_blocks, _state) do
    case Blocks.get_blocks_with_status(:download) do
      {:ok, blocks_to_download} ->
        blocks_to_download
        |> Enum.take(16)
        |> Enum.map(& &1.root)
        |> BlockDownloader.request_blocks_by_root()
        |> case do
          {:ok, signed_blocks} ->
            signed_blocks

          {:error, reason} ->
            Logger.debug("Block download failed: '#{reason}'")
            []
        end
        |> Enum.each(fn signed_block ->
          signed_block
          |> BlockInfo.from_block()
          |> BlockInfo.change_status(:download_blobs)
          |> Blocks.new_block_info()
        end)

      {:error, reason} ->
        Logger.error("[PendingBlocks] Failed to get blocks to download. Reason: #{reason}")
    end

    schedule_blocks_download()
    {:noreply, nil}
  end

  @impl true
  def handle_info(:download_blobs, _state) do
    case Blocks.get_blocks_with_status(:download_blobs) do
      {:ok, blocks_with_missing_blobs} ->
        blocks_with_blobs =
          blocks_with_missing_blobs
          |> Enum.sort_by(fn %BlockInfo{} = block_info -> block_info.signed_block.message.slot end)
          |> Enum.take(16)

        blobs_to_download = Enum.flat_map(blocks_with_blobs, &missing_blobs/1)

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

        # TODO: is it not possible that blobs were downloaded for one and not for another?
        if length(downloaded_blobs) == length(blobs_to_download) do
          Enum.each(blocks_with_blobs, fn block_info ->
            Blocks.change_status(block_info, :pending)
          end)
        end
    end

    schedule_blobs_download()
    {:noreply, nil}
  end

  ##########################
  ### Private Functions
  ##########################

  defp process_blocks() do
    case Blocks.get_blocks_with_status(:pending) do
      {:ok, blocks} ->
        blocks
        |> Enum.sort_by(fn %BlockInfo{} = block_info -> block_info.signed_block.message.slot end)
        |> Enum.each(&process_block/1)

      {:error, reason} ->
        Logger.error(
          "[Pending Blocks] Failed to get pending blocks to process. Reason: #{reason}"
        )
    end
  end

  defp process_block(block_info) do
    parent_root = block_info.signed_block.message.parent_root
    parent = Blocks.get_block_info(parent_root)

    cond do
      is_nil(parent) ->
        # TODO: add parent root to download list instead.
        %BlockInfo{root: parent_root, status: :download, signed_block: nil}
        |> Blocks.new_block_info()

      # If parent is invalid, block is invalid
      parent.status == :invalid ->
        Blocks.change_status(block_info, :invalid)

      # If all the other conditions are false, add block to fork choice
      parent.status == :transitioned ->
        case ForkChoice.on_block(block_info) do
          :ok ->
            Blocks.change_status(block_info, :transitioned)
            # Block is valid. We immediately check if we can process another block.
            process_blocks()

          {:error, reason} ->
            Logger.error("[PendingBlocks] Saving block as invalid #{reason}",
              slot: block_info.signed_block.message.slot,
              root: block_info.root
            )

            Blocks.change_status(block_info, :invalid)
        end
    end
  end

  @spec missing_blobs(BlockInfo.t()) :: [Types.BlobIdentifier.t()]
  defp missing_blobs(%BlockInfo{root: root, signed_block: signed_block}) do
    signed_block.message.body.blob_kzg_commitments
    |> Stream.with_index()
    |> Enum.filter(&blob_needs_download?(&1, root))
    |> Enum.map(&%Types.BlobIdentifier{block_root: root, index: elem(&1, 1)})
  end

  defp blob_needs_download?({commitment, index}, block_root) do
    case BlobDb.get_blob_sidecar(block_root, index) do
      {:ok, %{kzg_commitment: ^commitment}} ->
        false

      _ ->
        true
    end
  end

  defp schedule_blocks_processing() do
    Process.send_after(__MODULE__, :process_blocks, 500)
  end

  defp schedule_blobs_download() do
    Process.send_after(__MODULE__, :download_blobs, 500)
  end

  defp schedule_blocks_download() do
    Process.send_after(__MODULE__, :download_blocks, 1000)
  end
end
