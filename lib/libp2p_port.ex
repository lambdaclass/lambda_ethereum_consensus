defmodule LambdaEthereumConsensus.Libp2pPort do
  @moduledoc """
  A GenServer that allows other elixir processes to send and receive commands to/from
  the LibP2P server in Go. For now, it only supports subscribing and unsubscribing from
  topics.

  Requests are generated with an ID, which is returned when calling. Those IDs appear
  in the responses that might be listened to by other processes.
  """

  use GenServer

  alias Libp2pProto.{Command, Notification, SubscribeToTopic, UnsubscribeFromTopic}
  require Logger

  @port_name "libp2p_port/libp2p_port"

  ######################
  ### API
  ######################

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def subscribe_to_topic(topic_name) do
    data =
      Command.encode(%Command{
        id: UUID.uuid4(),
        c: {:subscribe, %SubscribeToTopic{name: topic_name}}
      })

    GenServer.cast(__MODULE__, {:send, data})
    {:ok, id}
  end

  def unsubscribe_from_topic(topic_name) do
    data =
      Command.encode(%Command{
        id: UUID.uuid4(),
        c: {:unsubscribe, %UnsubscribeFromTopic{name: topic_name}}
      })

    GenServer.cast(__MODULE__, {:send, data})
    {:ok, id}
  end

  ########################
  ### GenServer Callbacks
  ########################

  @impl GenServer
  def init([]) do
    {:ok,
     %{
       port: Port.open({:spawn, @port_name}, [:binary]),
       buffer: <<>>,
       waiting_for: :size
     }}
  end

  @impl GenServer
  def handle_cast({:send, data}, %{port: port} = state) do
    send_delimited(port, data)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({_port, {:data, data}}, %{buffer: buffer, waiting_for: size} = state) do
    new_state = handle_buffer(buffer <> data, size)
    {:noreply, state |> Map.merge(new_state)}
  end

  @impl GenServer
  def handle_info(other, state) do
    Logger.error(inspect(other))
    {:noreply, state}
  end

  ######################
  ### PRIVATE FUNCTIONS
  ######################

  # Recursively reads a binary buffer, according to its expected size. It returns the
  # unused parts of the buffer and the amount of bytes that we will need next.
  #
  # Arguments:
  # - buffer: binary buffer that arrived through the port.
  # - size: might be the :size atom if we're waiting for the size of the next message.
  #   if that's the case, we read 4 bytes of the buffer and continue parsing the rest
  #   of the available buffer. If it's an arbitrary number, we decode that amount of
  #   bytes and then keep parsing the rest of the buffer.
  #
  # Eventually, we will be waiting for a number of bytes and the buffer won't have enough
  # for us to parse that. When that point is reached, we return the new number of expected
  # bytes (4 or the next message size) and the bytes that weren't parsed for them to be joined
  # with the next bytes that arrive through the network.
  defp handle_buffer(buffer, :size) when byte_size(buffer) >= 4 do
    <<size::32, rest::binary>> = buffer
    handle_buffer(rest, size)
  end

  defp handle_buffer(buffer, size) when byte_size(buffer) >= size do
    <<message::binary-size(size), rest::binary>> = buffer

    # Note: this handling could be handled by a separate parser in a different async task.
    Notification.decode(message)
    |> handle_notification()

    handle_buffer(rest, :size)
  end

  # The clause that's executed when we don't have enough bytes.
  defp handle_buffer(buffer, size), do: %{buffer: buffer, waiting_for: size}

  defp handle_notification(%Libp2pProto.Notification{
         n: {:gossip, %Libp2pProto.GossipSub{topic: topic, message: message}}
       }) do
    Logger.info("[Topic] #{topic}: #{message}")
  end

  defp handle_notification(%Libp2pProto.Notification{
         n: {:response, %Libp2pProto.Response{id: id, success: success, message: message}}
       }) do
    success_txt = if success, do: "success", else: "failed"
    Logger.info("[Response] id #{id}: #{success_txt}. #{message}")
  end

  defp send_delimited(port, data) do
    size = byte_size(data)
    send_port(port, <<size::32-unsigned>>)
    send_port(port, data)
  end

  defp send_port(port, data), do: send(port, {self(), {:command, data}})
end
