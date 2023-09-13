defmodule LambdaEthereumConsensus.Libp2pPort do
  use GenServer

  alias Libp2pProto.{SubscribeToTopic, UnsubscribeFromTopic, Command, Notification}
  require Logger

  @port_name "libp2p_port/libp2p_port"

  ######################
  ### API
  ######################

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def subscribe_to_topic(topic_name) do
    data = Command.encode(%Command{id: UUID.uuid4(), c: {:subscribe, %SubscribeToTopic{name: topic_name}}})
    GenServer.cast(__MODULE__, {:send, data})
  end

  def unsubscribe_from_topic(topic_name) do
    data = Command.encode(%Command{id: UUID.uuid4(), c: {:unsubscribe, %UnsubscribeFromTopic{name: topic_name}}})
    GenServer.cast(__MODULE__, {:send, data})
  end

  ########################
  ### GenServer Callbacks
  ########################

  @impl GenServer
  def init([]) do
    {:ok, Port.open({:spawn, @port_name}, [:binary])}
  end

  @impl GenServer
  def handle_cast({:send, data}, port) do
    send_delimited(port, data)
    {:noreply, port}
  end

  @impl GenServer
  def handle_info({port, {:data, data}}, port) do
    Notification.decode(data)
    |> handle_notification()
    {:noreply, port}
  end

  def handle_info(other, port) do
    Logger.error(inspect(other))
    {:noreply, port}
  end

  ######################
  ### PRIVATE FUNCTIONS
  ######################

  defp handle_notification(%Libp2pProto.Notification{n: {:gossip, %Libp2pProto.GossipSub{topic: topic, message: message}}}) do
    Logger.info("[Topic] #{topic}: #{message}")
  end

  defp handle_notification(%Libp2pProto.Notification{n: {:response, %Libp2pProto.Response{id: id, success: success, message: message}}}) do
    success_txt = if success, do: "success", else: "failed"
    Logger.info("[Response] id #{id}: #{success_txt}. #{message}")
  end

  defp send_delimited(port, data) do
    size = String.length(data)
    send_port(port, <<size::32-unsigned>>)
    send_port(port, data)
  end

  defp send_port(port, data), do: send(port, {self(), {:command, data}})
end
