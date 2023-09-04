defmodule LambdaEthereumConsensus.GossipConsumer do
  @moduledoc """
  This module consumes events created by Subscriber.
  """
  use Broadway

  def start_link(%{gsub: gsub, topic: topic_name, payload: _} = opts)
      when is_binary(topic_name) do
    Broadway.start_link(__MODULE__,
      name: get_id(topic_name),
      context: opts,
      producer: [
        module: {LambdaEthereumConsensus.Subscriber, %{gsub: gsub, topic: topic_name}},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 1, max_demand: 1]
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
  def handle_message(_, %Broadway.Message{data: data} = message, %{
        topic: topic_name,
        payload: payload
      }) do
    data = Libp2p.message_data(data)

    # TODO: add handler modules

    with {:ok, decompressed} <- :snappyer.decompress(data) do
      case Ssz.from_ssz(decompressed, payload) do
        {:ok, res} -> IO.puts("[#{topic_name}] decoded: '#{res}'")
        _ -> data |> Base.encode16() |> then(&IO.puts("[#{topic_name}] raw: '#{&1}'"))
      end
    end

    message
  end

  defp get_id(topic_name) do
    __MODULE__
    |> Atom.to_string()
    |> then(&Enum.join([&1, ".", topic_name]))
    |> String.to_atom()
  end
end
