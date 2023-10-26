defmodule LambdaEthereumConsensus.P2P.Subscriber do
  @moduledoc """
  This module receives messages on a given topic, and broadcasts them as events.
  """
  use GenStage
  require Logger
  alias LambdaEthereumConsensus.Libp2pPort

  @impl true
  def init(%{topic: topic_name}) do
    :ok = Libp2pPort.subscribe_to_topic(topic_name)
    {:producer, %{topic: topic_name, queue: :queue.new(), demand: 0}}
  end

  @impl true
  def handle_demand(incoming_demand, %{demand: demand} = state) do
    pop_events(incoming_demand + demand, [], %{state | demand: 0})
  end

  defp pop_events(0, events, state) do
    {:noreply, events, state}
  end

  defp pop_events(incoming_demand, events, %{queue: queue, demand: 0} = state) do
    if :queue.is_empty(queue) do
      {:noreply, events, %{state | demand: incoming_demand}}
    else
      {{:value, item}, queue} = :queue.out(queue)
      events = [wrap_message(item) | events]
      pop_events(incoming_demand - 1, events, %{state | queue: queue})
    end
  end

  defp wrap_message(msg) do
    %Broadway.Message{
      data: msg,
      acknowledger: Broadway.NoopAcknowledger.init()
    }
  end

  @impl true
  def handle_info(
        {:gossipsub, {topic, message}},
        %{topic: topic, queue: queue, demand: demand} = state
      ) do
    queue = :queue.in(message, queue)
    pop_events(demand, [], %{state | queue: queue, demand: 0})
  end
end
