defmodule LambdaEthereumConsensus.Beacon.PendingBlocks do
  @moduledoc """
    Manages pending blocks and performs validations before adding them to the fork choice.

    The main purpose of this module is making sure that a blocks parent is already in the fork choice. If it's not, it will request it to the block downloader.
  """

  use GenServer

  require Logger
  alias LambdaEthereumConsensus.ForkChoice.Store
  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias LambdaEthereumConsensus.StateTransition.Misc

  @type state :: %{host: Libp2p.host(), pending_blocks: %{}}

  ##########################
  ### Public API
  ##########################

  def start_link(opts) do
    [host] = opts
    GenServer.start_link(__MODULE__, host, name: __MODULE__)
  end

  @spec add_block(SszTypes.BeaconBlock.t()) :: :ok
  def add_block(block) do
    GenServer.cast(__MODULE__, {:add_block, block})
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
  def init(host) do
    schedule_blocks_processing()

    {:ok, %{host: host, pending_blocks: %{}}}
  end

  @impl true
  def handle_cast({:add_block, block}, state) do
    {:ok, block_root} = Ssz.hash_tree_root(block)
    pending_blocks = Map.put(state.pending_blocks, block_root, block)
    {:noreply, Map.put(state, :pending_blocks, pending_blocks)}
  end

  @impl true
  def handle_call({:is_pending_block, block_root}, _from, state) do
    {:reply, Map.has_key?(state.pending_blocks, block_root), state}
  end

  @doc """
  Iterates through the pending blocks and adds them to the fork choice if their parent is already in the fork choice.
  """
  @impl true
  @spec handle_info(atom(), state()) :: {:noreply, state()}
  def handle_info(:process_blocks, state) do
    pending_blocks = state.pending_blocks

    blocks_to_remove =
      for {block_root, block} <- pending_blocks do
        cond do
          Store.has_block?(block_root) ->
            block_root

          Store.has_block?(block.parent_root) ->
            Store.on_block(block)
            block_root

          Map.has_key?(pending_blocks, block.parent_root) ->
            # parent block is in pending_blocks
            # do nothing
            nil

          true ->
            case BlockDownloader.request_block_by_root(block.parent_root, state.host) do
              {:ok, signed_block} ->
                Logger.info("Block downloaded: #{signed_block.message.slot}")
                block = signed_block.message
                add_block(block)

              {:error, reason} ->
                Logger.debug("Block download failed: '#{reason}'")
            end

            nil
        end
      end

    schedule_blocks_processing()
    {:noreply, Map.put(state, :pending_blocks, Map.drop(pending_blocks, blocks_to_remove))}
  end

  ##########################
  ### Private Functions
  ##########################

  defp schedule_blocks_processing do
    Process.send_after(self(), :process_blocks, 100)
  end
end
