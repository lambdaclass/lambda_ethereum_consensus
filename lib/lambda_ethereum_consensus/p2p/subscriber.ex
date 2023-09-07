defmodule LambdaEthereumConsensus.P2P.Subscriber do
  @moduledoc """
  This module receives messages on a given topic, and broadcasts them as events.
  """
  use GenStage
  require Logger

  @impl true
  def init(%{topic: topic_name, gsub: gsub}) do
    {:ok, topic} = Libp2p.pub_sub_join(gsub, topic_name)
    {:ok, subscription} = Libp2p.topic_subscribe(topic)

    {:producer, %{sub: subscription, queue: :queue.new(), demand: 0}}
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
  def handle_info({:sub, {:ok, message}}, %{queue: queue, demand: 0} = state) do
    queue = :queue.in(message, queue)
    {:noreply, [], %{state | queue: queue}}
  end

  def handle_info({:sub, {:ok, message}}, %{queue: queue, demand: demand} = state) do
    queue = :queue.in(message, queue)
    pop_events(demand, [], %{state | queue: queue, demand: 0})
  end

  def handle_info({:sub, {:error, reason}}, state) do
    Logger.error(reason)
    {:noreply, [], state}
  end
end
