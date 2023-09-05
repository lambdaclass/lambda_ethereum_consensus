defmodule LambdaEthereumConsensus.P2P.GossipHandler do
  @moduledoc """
  Module that implements the handle_message callback,
  used in the GossipConsumer module to handle messages.
  """
  def handle_message(topic_name, payload) do
    IO.puts("[#{topic_name}] decoded: '#{payload}'")
  end
end
