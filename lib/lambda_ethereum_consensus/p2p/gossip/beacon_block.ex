defmodule LambdaEthereumConsensus.P2P.Gossip.BeaconBlock do
  @moduledoc """
  This module handles beacon block gossipsub topics.
  """
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.Libp2pPort
  alias Types.SignedBeaconBlock

  use GenServer

  require Logger

  @type state :: %{topic: String.t(), slot: Types.slot()}

  ##########################
  ### Public API
  ##########################

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start() do
    GenServer.call(__MODULE__, :start)
  end

  @spec notify_slot(Types.slot()) :: :ok
  def notify_slot(slot) do
    GenServer.cast(__MODULE__, {:slot_transition, slot})
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl true
  @spec init(any()) :: {:ok, state()} | {:stop, any()}
  def init(_init_arg) do
    # TODO: this doesn't take into account fork digest changes
    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)
    slot = BeaconChain.get_current_slot()
    topic_name = "/eth2/#{fork_context}/beacon_block/ssz_snappy"
    Libp2pPort.join_topic(topic_name)
    {:ok, %{topic: topic_name, slot: slot}}
  end

  @impl true
  def handle_call(:start, _from, %{topic: topic_name} = state) do
    Libp2pPort.subscribe_to_topic(topic_name)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:slot_transition, slot}, state) do
    {:noreply, state |> Map.put(:slot, slot)}
  end

  @impl true
  def handle_info({:gossipsub, {_topic, msg_id, message}}, %{slot: slot} = state) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, beacon_block} <- Ssz.from_ssz(uncompressed, SignedBeaconBlock),
         :ok <- handle_beacon_block(beacon_block, slot) do
      # TODO: validate before accepting
      Libp2pPort.validate_message(msg_id, :accept)
    else
      {:error, _} -> Libp2pPort.validate_message(msg_id, :reject)
    end

    {:noreply, state}
  end

  @spec handle_beacon_block(SignedBeaconBlock.t(), Types.slot()) :: :ok | {:error, any}
  defp handle_beacon_block(%SignedBeaconBlock{message: block} = signed_block, current_slot) do
    # TODO: reject blocks from the future
    if block.slot > current_slot - ChainSpec.get("SLOTS_PER_EPOCH") do
      Logger.info("[Gossip] Block received", slot: block.slot)

      PendingBlocks.add_block(signed_block)
      :ok
    else
      Logger.warning("[Gossip] Block with slot #{block.slot} is too old", slot: current_slot)
      {:error, :block_too_old}
    end
  end
end
