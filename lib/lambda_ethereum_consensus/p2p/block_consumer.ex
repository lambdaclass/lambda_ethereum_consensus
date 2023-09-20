defmodule LambdaEthereumConsensus.P2P.BlockConsumer do
  @moduledoc """
  This module consumes events created by Discovery.
  """
  require Logger
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
        default: [concurrency: 1]
      ]
    )
  end

  @impl true
  def handle_message(_, %Broadway.Message{data: %SignedBeaconBlock{message: block}} = message, _) do
    Logger.notice("Block requested from peer: #{block.slot}")
    message
  end
end
