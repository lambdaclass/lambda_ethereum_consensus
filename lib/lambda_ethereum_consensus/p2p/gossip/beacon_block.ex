defmodule LambdaEthereumConsensus.P2P.Gossip.BeaconBlock do
  @moduledoc """
  This module handles beacon block gossipsub topics.
  """
  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias Types.SignedBeaconBlock

  require Logger
  @behaviour Handler

  ##########################
  ### Public API
  ##########################

  @impl true
  def handle_gossip_message(store, _topic, msg_id, message) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, signed_block} <- Ssz.from_ssz(uncompressed, SignedBeaconBlock),
         :ok <- validate(signed_block) do
      Logger.info("[Gossip] Block received, block.slot: #{signed_block.message.slot}.")
      Libp2pPort.validate_message(msg_id, :accept)
      PendingBlocks.add_block(store, signed_block)
    else
      {:ignore, reason} ->
        Logger.warning("[Gossip] Block ignored, reason: #{inspect(reason)}.")
        Libp2pPort.validate_message(msg_id, :ignore)
        store

      {:error, reason} ->
        Logger.warning("[Gossip] Block rejected, reason: #{inspect(reason)}.")
        Libp2pPort.validate_message(msg_id, :reject)
        store
    end
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

  def topic() do
    fork_context = ForkChoice.get_fork_digest() |> Base.encode16(case: :lower)
    "/eth2/#{fork_context}/beacon_block/ssz_snappy"
  end

  def topics(), do: [topic()]

  ##########################
  ### Private functions
  ##########################

  @spec validate(SignedBeaconBlock.t()) :: :ok | {:ignore, String.t()}
  defp validate(%SignedBeaconBlock{message: block}) do
    current_slot = ForkChoice.get_current_chain_slot()
    min_slot = current_slot - ChainSpec.get("SLOTS_PER_EPOCH")

    cond do
      # TODO incorporate MAXIMUM_GOSSIP_CLOCK_DISPARITY into future block calculations
      block.slot <= min_slot ->
        {:ignore,
         "Block too old: block.slot=#{block.slot}. Current slot: #{current_slot}. Minimum expected slot: #{min_slot}"}

      ForkChoice.future_chain_slot?(block.slot) ->
        {:ignore,
         "Block is from the future: block.slot=#{block.slot}. Current slot: #{current_slot}."}

      true ->
        :ok
    end
  end
end
