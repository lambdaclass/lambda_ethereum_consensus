defmodule LambdaEthereumConsensus.P2P.GossipHandler do
  def handle_message(topic_name, payload) do
    IO.puts("[#{topic_name}] decoded: '#{payload}'")
  end
end
