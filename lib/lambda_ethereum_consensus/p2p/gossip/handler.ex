defmodule LambdaEthereumConsensus.P2P.Gossip.Handler do
  @moduledoc """
  Module that implements the handle_message callback,
  used in the GossipConsumer module to handle messages.
  """
  require Logger

  alias Types.ProposerSlashing
  alias Types.AttesterSlashing
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.P2P.Gossip.OperationsCollector
  alias LambdaEthereumConsensus.Store.BlobDb
  alias LambdaEthereumConsensus.Utils.BitField

  alias Types.{
    AggregateAndProof,
    BlobSidecar,
    SignedAggregateAndProof,
    SignedBeaconBlock,
    SignedBLSToExecutionChange
  }

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

    # We are getting ~500 attestations in half a second. This is overwhelming the store GenServer at the moment.
    # ForkChoice.on_attestation(aggregate)

    Logger.debug(
      "[Gossip] Aggregate decoded. Total attestations: #{votes}",
      slot: slot,
      root: root
    )
  end

  def handle_bls_to_execution_change(%SignedBLSToExecutionChange{} = message) do
    # TODO: validate message first
    OperationsCollector.notify_bls_to_execution_change_gossip(message)
  end

  def handle_attester_slashing(%AttesterSlashing{} = message) do
    # TODO: validate message first
    OperationsCollector.notify_attester_slashing_gossip(message)
  end

  def handle_proposer_slashing(%ProposerSlashing{} = message) do
    # TODO: validate message first
    OperationsCollector.notify_proposer_slashing_gossip(message)
  end

  def handle_blob_sidecar(%BlobSidecar{index: blob_index} = blob, blob_index) do
    BlobDb.store_blob(blob)
    Logger.debug("[Gossip] Blob sidecar received, with index #{blob_index}")
  end

  # Ignore blobs with mismatched indices
  def handle_blob_sidecar(_, _), do: :ok
end
