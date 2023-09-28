defmodule LambdaEthereumConsensus.P2P.GossipHandler do
  @moduledoc """
  Module that implements the handle_message callback,
  used in the GossipConsumer module to handle messages.
  """
  require Logger

  alias LambdaEthereumConsensus.Store.BlockStore
  alias SszTypes.SignedBeaconBlock

  @spec handle_message(String.t(), SszTypes.SignedBeaconBlock.t()) :: :ok
  def handle_message("/eth2/bba4da96/beacon_block/ssz_snappy", %SignedBeaconBlock{message: block}) do
    Logger.notice("Block decoded: '#{block.slot}'")
    BlockStore.store_block(block)
  end

  def handle_message(topic_name, payload) do
    payload
    |> inspect(limit: :infinity)
    |> then(&"[#{topic_name}] decoded: '#{&1}'")
    |> Logger.debug()
  end
end
