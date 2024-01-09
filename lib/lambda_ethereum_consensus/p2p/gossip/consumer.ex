defmodule LambdaEthereumConsensus.P2P.Gossip.Consumer do
  @moduledoc """
  This module consumes events created by Subscriber.
  """
  require Logger
  use Broadway

  def start_link(%{topic: topic_name, ssz_type: _, handler: _} = opts)
      when is_binary(topic_name) do
    Broadway.start_link(__MODULE__,
      name: get_id(topic_name),
      context: opts,
      producer: [
        module: {LambdaEthereumConsensus.P2P.Subscriber, %{topic: topic_name}},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 8, max_demand: 1]
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
        topic: topic,
        ssz_type: ssz_type,
        handler: handler
      }) do
    with {:ok, decompressed} <- :snappyer.decompress(data),
         {:ok, res} <- Ssz.from_ssz(decompressed, ssz_type),
         :ok <- handler.(res) do
      message
    else
      {:error, reason} ->
        data
        |> Base.encode16()
        |> then(&"[#{topic}] (err: #{reason}) raw: '#{&1}'")
        |> Logger.error()

        Broadway.Message.failed(message, reason)
    end
  end

  defp get_id(topic_name) do
    __MODULE__
    |> Atom.to_string()
    |> then(&Enum.join([&1, ".", topic_name]))
    |> String.to_atom()
  end
end
