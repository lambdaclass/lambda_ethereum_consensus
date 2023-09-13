defmodule LambdaEthereumConsensus.Handlers.BlockHandler do
  @moduledoc """
  Module that handles blocks that are received through the gossipsub topic.
  """
  alias LambdaEthereumConsensus.Store.BlockStore
  alias SszTypes.SignedBeaconBlock

  require Logger

  @spec handle_message(String.t(), SszTypes.SignedBeaconBlock.t()) :: :ok
  def handle_message(_topic_name, %SignedBeaconBlock{message: block}) do
    Logger.notice("Block decoded: '#{inspect(block.slot)}'")
    BlockStore.store_block(block)
  end
end
