defmodule LambdaEthereumConsensus.P2P.Gossip.BeaconBlock do
  @moduledoc """
  This module handles beacon block gossipsub topics.
  """
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias Types.SignedBeaconBlock

  use GenServer

  require Logger
  @behaviour Handler

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

  @impl true
  def handle_gossip_message(topic, msg_id, message) do
    send(__MODULE__, {:gossipsub, {topic, msg_id, message}})
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
    Libp2pPort.subscribe_to_topic(topic_name, __MODULE__)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:on_tick, {slot, _}}, state) do
    {:noreply, state |> Map.put(:slot, slot)}
  end

  @impl true
  def handle_info({:gossipsub, {_topic, msg_id, message}}, %{slot: slot} = state) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, signed_block} <- Ssz.from_ssz(uncompressed, SignedBeaconBlock),
         :ok <- validate(signed_block, slot) do
      Logger.info("[Gossip] Block received", slot: signed_block.message.slot)
      Libp2pPort.validate_message(msg_id, :accept)
      PendingBlocks.add_block(signed_block)
    else
      {:ignore, reason} ->
        Logger.warning("[Gossip] Block ignored, reason: #{inspect(reason)}", slot: slot)
        Libp2pPort.validate_message(msg_id, :ignore)

      {:error, reason} ->
        Logger.warning("[Gossip] Block rejected, reason: #{inspect(reason)}", slot: slot)
        Libp2pPort.validate_message(msg_id, :reject)
    end

    {:noreply, state}
  end

  @spec validate(SignedBeaconBlock.t(), Types.slot()) :: :ok | {:error, any}
  defp validate(%SignedBeaconBlock{message: block}, current_slot) do
    cond do
      # TODO incorporate MAXIMUM_GOSSIP_CLOCK_DISPARITY into future block calculations
      block.slot <= current_slot - ChainSpec.get("SLOTS_PER_EPOCH") -> {:ignore, :block_too_old}
      block.slot > current_slot -> {:ignore, :block_from_future}
      true -> :ok
    end
  end
end
