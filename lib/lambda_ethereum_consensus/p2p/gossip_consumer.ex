defmodule LambdaEthereumConsensus.GossipConsumer do
  @moduledoc """
  This module consumes events created by Subscriber.
  """
  use Broadway

  def start_link(%{topic: topic_name}) when is_binary(topic_name) do
    Broadway.start_link(__MODULE__,
      name: get_id(topic_name),
      producer: [
        module: {LambdaEthereumConsensus.Subscriber, %{topic: topic_name}},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 1]
      ]
    )
  end

  def child_spec(%{topic: topic_name} = arg) do
    %{
      id: get_id(topic_name),
      start: {__MODULE__, :start_link, [arg]}
    }
  end

  @impl true
  def handle_message(_, %Broadway.Message{data: data} = message, _) do
    data
    |> Libp2p.message_data()
    |> Base.encode16()
    |> IO.inspect()

    message
  end

  defp get_id(topic_name) do
    __MODULE__
    |> Atom.to_string()
    |> then(&Enum.join([&1, ".", topic_name]))
    |> String.to_atom()
  end
end
