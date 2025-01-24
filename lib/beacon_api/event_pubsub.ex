defmodule BeaconApi.EventPubSub do
  @moduledoc """
  Event listener for aggregating and sending events for SSE subscribers.

  TODO: This depends on `event_bus` and `sse`, but it could be easily switched later:
  - `event_bus` we could move to phoenix pubsub
  - `sse` we could just implement it ourselves using Plug.Conn.chunk and Plug.Conn.send_chunked

  The idea is to have a single place to publish events, and then a method for a connection to subscribe to them.
  """

  require Logger
  alias EventBus.Model.Event
  alias LambdaEthereumConsensus.Store
  alias SSE.Chunk
  alias Types.StateInfo

  @type topic() :: atom()
  @type event_data() :: any()

  # This is also dependant on the already needed event_bus compile time config
  @implemented_topics Application.compile_env!(:event_bus, :topics)

  defguard is_implemented_topic(topic) when topic in @implemented_topics

  @spec implemented_topics() :: list(topic())
  def implemented_topics(), do: @implemented_topics

  @doc """
  Publish an event to the event bus.

  TODO: We might want a noop if there are no subscribers for a topic.
  """
  @spec publish(topic(), event_data()) :: :ok | {:error, atom()}
  def publish(:finalized_checkpoint = topic, %{root: block_root, epoch: epoch}) do
    case Store.BlockStates.get_state_info(block_root) do
      %StateInfo{root: state_root} ->
        data = %{
          block: BeaconApi.Utils.hex_encode(block_root),
          state: BeaconApi.Utils.hex_encode(state_root),
          epoch: epoch,
          execution_optimistic: false
        }

        chunk = %Chunk{event: topic, data: [Jason.encode!(data)]}
        event = %Event{id: UUID.uuid4(), data: chunk, topic: topic}

        EventBus.notify(event)

      nil ->
        Logger.error("State not available for block", root: block_root)

        {:error, :state_not_available}
    end
  end

  def publish(_topic, _event_data), do: {:error, :unsupported_topic}

  @doc """
  Subscribe to a topic for stream events in an sse connection.
  """
  @spec sse_subscribe(Plug.Conn.t(), topic()) :: Plug.Conn.t()
  def sse_subscribe(conn, topic) do
    conn
    |> SSE.stream({[topic], %Chunk{data: []}})
  end
end
