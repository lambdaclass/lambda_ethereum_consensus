defmodule LambdaEthereumConsensus.P2P.Discovery do
  @moduledoc """
  This module discovers new peers, and broadcasts them as events.
  """
  use GenStage
  alias LambdaEthereumConsensus.Libp2pPort

  @impl true
  def init(_opts) do
    Libp2pPort.set_new_peer_handler(self())
    {:producer, {0, []}}
  end

  @impl true
  def handle_demand(incoming_demand, {demand, found_peers}) do
    {messages, new_state} = balance_demand({demand + incoming_demand, found_peers})
    {:noreply, messages, new_state}
  end

  @impl true
  def handle_info({:new_peer, peer_id}, {demand, found_peers}) do
    {messages, new_state} = balance_demand({demand, [peer_id | found_peers]})
    {:noreply, messages, new_state}
  end

  defp balance_demand({0, _} = state), do: state
  defp balance_demand({_, []} = state), do: state

  defp balance_demand({demand, [peer | peers]}) do
    message = wrap_message(peer)
    {messages, new_state} = balance_demand({demand - 1, peers})
    {[message | messages], new_state}
  end

  defp wrap_message(msg) do
    %Broadway.Message{
      data: msg,
      acknowledger: Broadway.NoopAcknowledger.init()
    }
  end
end
