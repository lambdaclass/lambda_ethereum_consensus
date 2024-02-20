defmodule LambdaEthereumConsensus.P2P.Gossip.Handler do
  @moduledoc """
  Module that implements the handle_message callback,
  used in the GossipConsumer module to handle messages.
  """
  require Logger

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.Utils.BitField
  alias Types.{AggregateAndProof, SignedAggregateAndProof, SignedBeaconBlock}

  def handle_beacon_block(%SignedBeaconBlock{message: block} = signed_block) do
    current_slot = BeaconChain.get_current_slot()

    if block.slot > current_slot - ChainSpec.get("SLOTS_PER_EPOCH") do
      Logger.info("[Gossip] Block received", slot: block.slot)

      PendingBlocks.add_block(signed_block)
    end

    :ok
  end

  def handle_beacon_aggregate_and_proof(%SignedAggregateAndProof{
        message: %AggregateAndProof{aggregate: aggregate}
      }) do
    votes = BitField.count(aggregate.aggregation_bits)
    slot = aggregate.data.slot
    root = aggregate.data.beacon_block_root |> Base.encode16()

    # We are getting ~500 attestations in half a second. This is overwheling the store GenServer at the moment.
    # Store.on_attestation(aggregate)

    Logger.debug(
      "[Gossip] Aggregate decoded. Total attestations: #{votes}",
      slot: slot,
      root: root
    )
  end
end
