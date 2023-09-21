defmodule LambdaEthereumConsensus.P2P.BlockConsumer do
  @moduledoc """
  This module consumes events created by Discovery.
  """
  require Logger
  alias LambdaEthereumConsensus.Store.BlockStore
  alias SszTypes.SignedBeaconBlock
  use Broadway

  def start_link([host]) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {LambdaEthereumConsensus.P2P.BlockDownloader, [host]},
        concurrency: 1
      ],
      processors: [
        # TODO: demand should map 1-to-1 the amount of blocks?
        default: [concurrency: 1, max_demand: 1]
      ]
    )
  end

  @impl true
  def handle_message(_, %Broadway.Message{data: %SignedBeaconBlock{message: block}} = message, _) do
    Logger.notice("Block requested: '#{block.slot}'")
    BlockStore.store_block(block)
    message
  end
end
