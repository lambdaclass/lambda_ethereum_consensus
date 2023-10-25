defmodule LambdaEthereumConsensus.P2P.GossipHandler do
  @moduledoc """
  Module that implements the handle_message callback,
  used in the GossipConsumer module to handle messages.
  """
  require Logger

  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.ForkChoice.Store
  alias SszTypes.{AggregateAndProof, SignedAggregateAndProof, SignedBeaconBlock}

  @spec handle_message(String.t(), struct) :: :ok
  def handle_message(topic_name, payload)

  def handle_message("/eth2/bba4da96/beacon_block/ssz_snappy", %SignedBeaconBlock{message: block}) do
    current_slot = Store.get_current_slot()

    if block.slot > current_slot - ChainSpec.get("SLOTS_PER_EPOCH") do
      Logger.info("[Gossip] Block decoded for slot #{block.slot}")

      PendingBlocks.add_block(block)
    end

    :ok
  end

  def handle_message(
        "/eth2/bba4da96/beacon_aggregate_and_proof/ssz_snappy",
        %SignedAggregateAndProof{message: %AggregateAndProof{aggregate: aggregate}}
      ) do
    votes = count_bits(aggregate.aggregation_bits)
    slot = aggregate.data.slot
    root = aggregate.data.beacon_block_root |> Base.encode16()

    Logger.debug(
      "[Gossip] Aggregate decoded for slot #{slot}. Root: #{root}. Total attestations: #{votes}"
    )
  end

  def handle_message(topic_name, payload) do
    payload
    |> inspect(limit: :infinity)
    |> then(&"[#{topic_name}] decoded: '#{&1}'")
    |> Logger.debug()
  end

  defp count_bits(bitstring),
    do: for(<<bit::1 <- bitstring>>, do: bit) |> Enum.sum()
end
