defmodule LambdaEthereumConsensus.Metrics do
  @moduledoc """
  Basic telemetry metric generation to be used across the node.
  """
  alias Types.BlockInfo

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

  def block_status(%BlockInfo{root: root, status: new_status, signed_block: nil}, old_status),
    do: block_status(root, nil, old_status, new_status)

  def block_status(
        %BlockInfo{root: root, status: new_status, signed_block: signed_block},
        old_status
      ),
      do: block_status(root, signed_block.message.slot, old_status, new_status)

  def block_status(root, slot, old_status, new_status) do
    block_status_execute(root, old_status, slot, 0)
    block_status_execute(root, new_status, slot, 1)
  end

  def block_status(root, slot, new_status) do
    block_status_execute(root, new_status, slot, 1)
  end

  defp block_status_execute(root, status, slot, value) do
    hex_root = Base.encode16(root)

    :telemetry.execute([:blocks, :status], %{total: value}, %{
      id: hex_root,
      mainstat: status,
      color: map_color(status),
      title: slot,
      subtitle: hex_root
    })
  end

  def block_relationship(parent_id, child_id) do
    hex_parent_id = parent_id |> Base.encode16()
    hex_child_id = child_id |> Base.encode16()

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
