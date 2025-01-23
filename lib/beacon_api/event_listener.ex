defmodule BeaconApi.EventPubSub do
  @moduledoc """
  Event listener for aggregating and sending events for SSE subscribers.

  This depends on `event_bus` and `sse`, but it could be easily switched later.

  The idea is to have a single place to publish events, and then a method for a connection to subscribe to them.
  """

  alias EventBus.Model.Event
  alias SSE.Chunk

  @type topic() :: atom()
  @type event_data() :: any()

  @doc """
  Publish an event to the event bus.

  TODO: We might want a noop if there are no subscribers for a topic.
  """
  @spec publish(topic(), event_data()) :: :ok | {:error, atom()}
  def publish(:finalized_checkpoint = topic, %{root: root, epoch: epoch}) do
    data = %{root: BeaconApi.Utils.hex_encode(root), epoch: epoch}
    chunk = %Chunk{data: [Jason.encode!(data)]}
    event = %Event{id: UUID.uuid4(), data: chunk, topic: topic}

    EventBus.notify(event)
  end

  def publish(_topic, _event_data), do: {:error, :unsupported_topic}

  @doc """
  Subscribe to a topic for stream events in an sse connection.
  """
  @spec sse_subscribe(Plug.Conn.t(), topic(), event_data()) :: Plug.Conn.t()
  def sse_subscribe(conn, topic), do: SSE.stream(conn, {[topic], %Chunk{data: []}})
end
