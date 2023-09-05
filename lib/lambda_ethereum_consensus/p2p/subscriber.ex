defmodule LambdaEthereumConsensus.P2P.Subscriber do
  @moduledoc """
  This module receives messages on a given topic, and broadcasts them as events.
  """
  use GenStage

  @impl true
  def init(%{topic: topic_name, gsub: gsub}) do
    {:ok, topic} = Libp2p.pub_sub_join(gsub, topic_name)
    {:ok, subscription} = Libp2p.topic_subscribe(topic)
    {:producer, subscription}
  end

  @impl true
  def handle_demand(incoming_demand, subscription) do
    messages =
      for _ <- 1..incoming_demand do
        {:ok, msg} = Libp2p.subscription_next(subscription)

        wrap_message(msg)
      end

    {:noreply, messages, subscription}
  end

  defp wrap_message(msg) do
    %Broadway.Message{
      data: msg,
      acknowledger: Broadway.NoopAcknowledger.init()
    }
  end
end
