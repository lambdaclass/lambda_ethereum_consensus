defmodule LambdaEthereumConsensus.P2P.Gossip.BeaconBlock do
  @moduledoc """
  This module handles beacon block gossipsub topics.
  """
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias Types.SignedBeaconBlock

  require Logger
  @behaviour Handler

  ##########################
  ### Public API
  ##########################

  @impl true
  def handle_gossip_message(_topic, msg_id, message) do
    handle_beacon_block(msg_id, message)
    :ok
  end

  @spec join_topic() :: :ok
  def join_topic() do
    # TODO: this doesn't take into account fork digest changes
    topic_name = topic()
    Libp2pPort.join_topic(self(), topic_name)
  end

  @spec subscribe_to_topic() :: :ok | :error
  def subscribe_to_topic() do
    topic()
    |> Libp2pPort.subscribe_to_topic(__MODULE__)
    |> case do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("[Gossip] Subscription failed: '#{reason}'")
        :error
    end
  end

  ##########################
  ### Private functions
  ##########################

  defp handle_beacon_block(msg_id, message) do
    slot = BeaconChain.get_current_slot()

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
  end

  defp topic() do
    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)
    "/eth2/#{fork_context}/beacon_block/ssz_snappy"
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
