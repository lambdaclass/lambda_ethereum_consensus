defmodule LambdaEthereumConsensus.P2P.Gossip.Subscriber do
  alias LambdaEthereumConsensus.P2P.Gossip.Dispatcher
  alias LambdaEthereumConsensus.P2P.Gossip.Handler

  @behaviour Handler

  def handle_gossip_message(msg_id, message) do
    IO.puts("Handling message #{msg_id}: #{message}")
  end

  def subscribe_to_topic(topic) do
    Dispatcher.subscribe_to_topic(__MODULE__, topic)
  end
end
