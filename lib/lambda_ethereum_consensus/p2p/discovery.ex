defmodule LambdaEthereumConsensus.P2P.Discovery do
  @moduledoc """
  This module discovers new peers, and broadcasts them as events.
  """
  use GenStage

  @impl true
  def init(_opts) do
    config = Application.get_env(:lambda_ethereum_consensus, __MODULE__)

    {:ok, listener} =
      Libp2p.listen_v5("0.0.0.0:#{config[:port]}", config[:bootnodes])

    {:ok, iterator} = Libp2p.listener_random_nodes(listener)
    # NOTE: this stream isn't pure
    mut_stream =
      iterator
      |> Stream.unfold(&get_next_node/1)
      |> Stream.map(&wrap_message/1)

    {:producer, mut_stream}
  end

  defp get_next_node(iterator) do
    if !Libp2p.iterator_next(iterator) do
      raise "no more nodes!"
    end

    {:ok, node} = Libp2p.iterator_node(iterator)
    {:ok, id} = Libp2p.node_id(node)
    {:ok, addrs} = Libp2p.node_multiaddr(node)
    element = {id, addrs}

    {element, iterator}
  end

  @impl true
  def handle_demand(incoming_demand, mut_stream) do
    messages =
      mut_stream
      |> Enum.take(incoming_demand)

    {:noreply, messages, mut_stream}
  end

  defp wrap_message(msg) do
    %Broadway.Message{
      data: msg,
      acknowledger: Broadway.NoopAcknowledger.init()
    }
  end
end
