defmodule LambdaEthereumConsensus.Metrics do
  @moduledoc """
  Basic telemetry metric generation to be used across the node.
  """

  def tracer({:add_peer, %{}}) do
    :telemetry.execute([:network, :pubsub_peers], %{}, %{result: "add"})
  end

  def tracer({:remove_peer, %{}}) do
    :telemetry.execute([:network, :pubsub_peers], %{}, %{result: "remove"})
  end

  def tracer({:joined, %{topic: topic}}) do
    :telemetry.execute([:network, :pubsub_topic_active], %{active: 1}, %{
      topic: get_topic_name(topic)
    })
  end

  def tracer({:left, %{topic: topic}}) do
    :telemetry.execute([:network, :pubsub_topic_active], %{active: -1}, %{
      topic: get_topic_name(topic)
    })
  end

  def tracer({:grafted, %{topic: topic}}) do
    :telemetry.execute([:network, :pubsub_topics_graft], %{}, %{topic: get_topic_name(topic)})
  end

  def tracer({:pruned, %{topic: topic}}) do
    :telemetry.execute([:network, :pubsub_topics_prune], %{}, %{topic: get_topic_name(topic)})
  end

  def tracer({:deliver_message, %{topic: topic}}) do
    :telemetry.execute([:network, :pubsub_topics_deliver_message], %{}, %{
      topic: get_topic_name(topic)
    })
  end

  def tracer({:duplicate_message, %{topic: topic}}) do
    :telemetry.execute([:network, :pubsub_topics_duplicate_message], %{}, %{
      topic: get_topic_name(topic)
    })
  end

  def tracer({:reject_message, %{topic: topic}}) do
    :telemetry.execute([:network, :pubsub_topics_reject_message], %{}, %{
      topic: get_topic_name(topic)
    })
  end

  def tracer({:un_deliverable_message, %{topic: topic}}) do
    :telemetry.execute([:network, :pubsub_topics_un_deliverable_message], %{}, %{
      topic: get_topic_name(topic)
    })
  end

  def tracer({:validate_message, %{topic: topic}}) do
    :telemetry.execute([:network, :pubsub_topics_validate_message], %{}, %{
      topic: get_topic_name(topic)
    })
  end

  def get_topic_name(topic) do
    case topic |> String.split("/") |> Enum.fetch(3) do
      {:ok, name} -> name
      :error -> topic
    end
  end
end
