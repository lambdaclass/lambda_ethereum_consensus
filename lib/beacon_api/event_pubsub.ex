defmodule BeaconApi.EventPubSub do
  @moduledoc """
  Event listener for aggregating and sending events for SSE subscribers.

  TODO: (#1368) This depends on `event_bus` and `sse`, but it could be easily switched later:
  - `event_bus` we could move to phoenix pubsub
  - `sse` we could just implement it ourselves using Plug.Conn.chunk and Plug.Conn.send_chunked

  The idea is to have a single place to publish events, and then a method for a connection to subscribe to them.
  """

  require Logger
  alias EventBus.Model.Event
  alias SSE.Chunk

  @type topic() :: String.t() | atom()
  @type topics() :: list(topic())
  @type event_data() :: any()

  # This is also dependant on the already needed event_bus compile time config,
  # we maintain them as strings for convienience
  @implemented_topics Application.compile_env!(:event_bus, :topics) |> Enum.map(&Atom.to_string/1)

  @spec implemented_topics() :: topics()
  def implemented_topics(), do: @implemented_topics

  @spec implemented_topic?(topic()) :: boolean()
  def implemented_topic?(topic) when is_atom(topic), do: implemented_topic?(Atom.to_string(topic))
  def implemented_topic?(topic) when is_binary(topic), do: topic in @implemented_topics

  @doc """
  Publish an event to the event bus.

  TODO: We might want a noop if there are no subscribers for a topic.
  """
  @spec publish(topic(), event_data()) :: :ok
  def publish(:finalized_checkpoint = topic, %{
        block_root: block_root,
        state_root: state_root,
        epoch: epoch
      }) do
    data = %{
      block: BeaconApi.Utils.hex_encode(block_root),
      state: BeaconApi.Utils.hex_encode(state_root),
      epoch: Integer.to_string(epoch),
      # TODO: this is a placeholder, we need to get if the execution is optimistic or not
      execution_optimistic: false
    }

    chunk = %Chunk{event: topic, data: [Jason.encode!(data)]}
    event = %Event{id: UUID.uuid4(), data: chunk, topic: topic}

    EventBus.notify(event)
  end

  def publish(:block = topic, %{root: block_root, slot: slot}) do
    data = %{
      block: BeaconApi.Utils.hex_encode(block_root),
      slot: Integer.to_string(slot),
      # TODO: this is a placeholder, we need to get if the execution is optimistic or not
      execution_optimistic: false
    }

    chunk = %Chunk{event: topic, data: [Jason.encode!(data)]}
    event = %Event{id: UUID.uuid4(), data: chunk, topic: topic}

    EventBus.notify(event)
  end

  def publish(_topic, _event_data), do: {:error, :unsupported_topic}

  @doc """
  Subscribe to a topic for stream events in an sse connection.
  """
  @spec sse_subscribe(Plug.Conn.t(), topics()) :: Plug.Conn.t()
  def sse_subscribe(conn, topics) when is_list(topics),
    do: SSE.stream(conn, {topics, %Chunk{data: []}})
end
