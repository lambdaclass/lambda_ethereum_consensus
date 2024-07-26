defmodule LambdaEthereumConsensus.Metrics do
  @moduledoc """
  Basic telemetry metric generation to be used across the node.
  """
  alias LambdaEthereumConsensus.Store.Blocks
  require Logger

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

  def block_status(root, slot, new_status) do
    block_status_execute(root, new_status, slot, 1)
  end

  @doc """
  - Sets the old status to '0' to deactivate it and sets the new status to '1' so that we can filter the Grafana table.
  - If the old status is ':download', it will be deactivated with a 'nil' slot, since that's how it was activated.
  """
  def block_status(root, slot, :download, new_status) do
    block_status_execute(root, :download, nil, 0)
    block_status_execute(root, new_status, slot, 1)
  end

  def block_status(root, slot, old_status, new_status) do
    block_status_execute(root, old_status, slot, 0)
    block_status_execute(root, new_status, slot, 1)
  end

  def block_relationship(nil, _), do: :ok

  def block_relationship(parent_root, root) do
    # If we try to add an edge to a non-existent node, it will crash.
    if Blocks.get_block_info(parent_root) do
      hex_parent_root = parent_root |> Base.encode16()
      hex_root = root |> Base.encode16()

      :telemetry.execute([:blocks, :relationship], %{total: 1}, %{
        id: hex_root <> hex_parent_root,
        source: hex_parent_root,
        target: hex_root
      })
    end
  end

  def span_operation(handler, transition, operation, f) do
    :telemetry.span([:fork_choice, :latency], %{}, fn ->
      {f.(), %{handler: handler, transition: transition, operation: operation}}
    end)
  end

  def handler_span(module, action, f) do
    :telemetry.span([:libp2pport, :handler], %{}, fn ->
      {f.(), %{module: module, action: action}}
    end)
  end

  defp block_status_execute(root, status, slot, value) do
    hex_root = Base.encode16(root)

    Logger.debug(
      "[Metrics] slot = #{inspect(slot)}, status = #{inspect(status)}, value = #{inspect(value)}"
    )

    :telemetry.execute([:blocks, :status], %{total: value}, %{
      id: hex_root,
      mainstat: status,
      color: map_color(status),
      title: slot,
      detail__root: hex_root
    })
  end

  defp map_color(:transitioned), do: "blue"
  defp map_color(:pending), do: "green"
  defp map_color(:download_blobs), do: "yellow"
  defp map_color(:download), do: "orange"
  defp map_color(:invalid), do: "red"
end
