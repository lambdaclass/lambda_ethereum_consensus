defmodule LambdaEthereumConsensus.P2P.Subscriber do
  @moduledoc """
  This module receives messages on a given topic, and broadcasts them as events.
  """
  use GenStage

  @impl true
  def init(%{topic: topic_name, gsub: gsub}) do
    {:ok, topic} = Libp2p.pub_sub_join(gsub, topic_name)
    {:ok, subscription} = Libp2p.topic_subscribe(topic)
    # NOTE: this stream isn't pure
    mut_stream =
      subscription
      |> Stream.unfold(&get_next_msg/1)
      |> Stream.map(&wrap_message/1)

    {:producer, mut_stream}
  end

  defp get_next_msg(subscription) do
    {:ok, msg} = Libp2p.subscription_next(subscription)

    {msg, subscription}
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
