defmodule LambdaEthereumConsensus.Metrics do
  @moduledoc """
  Basic telemetry metric generation to be used across the node.
  """
  alias LambdaEthereumConsensus.Store.BlockDb

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

  def block_status(root, slot, status) do
    hex_root = root |> Base.encode16()

    color_str = map_color(status) |> IO.inspect()

    :telemetry.execute([:blocks, :status], %{total: 1}, %{
      id: hex_root,
      mainstat: status,
      color: color_str,
      title: slot,
      subtitle: hex_root
    })
  end

  def block_status(root, slot, old_status, new_status) do
    hex_root = root |> Base.encode16()

    color_str = map_color(old_status) |> IO.inspect()

    :telemetry.execute([:blocks, :status], %{total: 0}, %{
      id: hex_root,
      mainstat: old_status,
      color: color_str,
      title: slot,
      subtitle: hex_root
    })

    color_str = map_color(new_status) |> IO.inspect()

    :telemetry.execute([:blocks, :status], %{total: 1}, %{
      id: hex_root,
      mainstat: new_status,
      color: color_str,
      title: slot,
      subtitle: hex_root
    })
  end

  def block_relationship(parent_id, child_id) do
    hex_parent_id = parent_id |> Base.encode16()
    hex_child_id = child_id |> Base.encode16()

    if BlockDb.has_block_info?(parent_id) and BlockDb.has_block_info?(child_id),
      do:
        :telemetry.execute([:blocks, :relationship], %{total: 1}, %{
          id: hex_child_id <> hex_parent_id,
          source: hex_parent_id,
          target: hex_child_id
        })
  end

  defp map_color(:transitioned), do: "blue"
  defp map_color(:pending), do: "green"
  defp map_color(:download_blobs), do: "yellow"
  defp map_color(:download), do: "orange"
  defp map_color(:invalid), do: "red"
end
