defmodule LambdaEthereumConsensus.Beacon.PendingBlocks do
  @moduledoc """
    Manages pending blocks and performs validations before adding them to the fork choice.

    The main purpose of this module is making sure that a blocks parent is already in the fork choice. If it's not, it will request it to the block downloader.
  """

  use GenServer

  require Logger
  alias LambdaEthereumConsensus.P2P.BlockDownloader

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
          in_fork_choice?(block_root) ->
            block_root

          in_fork_choice?(block.parent_root) ->
            add_to_fork_choice(block)
            block_root

          # remove from state
          Map.has_key?(pending_blocks, block.parent_root) ->
            # parent block is in pending_blocks
            # do nothing
            nil

          true ->
            case BlockDownloader.request_block_by_root(block.parent_root, state.host) do
              {:ok, signed_block} ->
                Logger.debug("Block downloaded: #{signed_block.message.slot}")
                block = signed_block.message
                add_block(block)

              {:error, reason} ->
                Logger.error("Block download failed: '#{reason}'")
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
    Process.send_after(self(), :process_blocks, 1000)
  end

  @spec in_fork_choice?(SszTypes.root()) :: boolean()
  defp in_fork_choice?(block_hash) do
    # TODO
    # add to fork choice
    # adding this to make dialyzer happy
    block_hash == <<>>
  end

  @spec add_to_fork_choice(SszTypes.BeaconBlock.t()) :: :ok
  defp add_to_fork_choice(_block) do
    # TODO
    :ok
  end
end
