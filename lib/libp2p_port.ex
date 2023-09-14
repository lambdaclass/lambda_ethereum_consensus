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
    id = UUID.uuid4()

    data =
      Command.encode(%Command{
        id: id,
        c: {:subscribe, %SubscribeToTopic{name: topic_name}}
      })

    GenServer.cast(__MODULE__, {:send, data})
    {:ok, id}
  end

  def unsubscribe_from_topic(topic_name) do
    id = UUID.uuid4()

    data =
      Command.encode(%Command{
        id: id,
        c: {:unsubscribe, %UnsubscribeFromTopic{name: topic_name}}
      })

    GenServer.cast(__MODULE__, {:send, data})
    {:ok, id}
  end

  ########################
  ### GenServer Callbacks
  ########################

  @impl GenServer
  def init([]), do: {:ok, Port.open({:spawn, @port_name}, [:binary, {:packet, 4}])}

  @impl GenServer
  def handle_cast({:send, data}, port) do
    send_port(port, data)
    {:noreply, port}
  end

  @impl GenServer
  def handle_info({_port, {:data, data}}, port) do
    data
    |> Notification.decode()
    |> handle_notification()

    {:noreply, port}
  end

  @impl GenServer
  def handle_info(other, port) do
    Logger.error(inspect(other))
    {:noreply, port}
  end

  ######################
  ### PRIVATE FUNCTIONS
  ######################

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

  defp send_port(port, data), do: send(port, {self(), {:command, data}})
end
