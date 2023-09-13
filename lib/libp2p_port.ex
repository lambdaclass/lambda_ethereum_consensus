defmodule LambdaEthereumConsensus.Libp2pPort do
  use GenServer

  @port_name "libp2p_port/libp2p_port"

  alias Libp2pProto.{SubscribeToTopic, UnsubscribeFromTopic, Command, Notification}

  require Logger

  ######################
  ### API
  ######################

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def subscribe_to_topic(topic_name) do
    data = Command.encode(%Command{id: "id", c: %{subscribe: %SubscribeToTopic{name: topic_name}}})
    GenServer.cast(__MODULE__, {:send, data})
  end

  def unsubscribe_from_topic(topic_name) do
    data = Command.encode(%Command{id: "id", c: %{unsubscribe: %UnsubscribeFromTopic{name: topic_name}}})
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
    decoded = Notification.decode(data)
    Logger.debug("This is the decoded data: #{inspect(decoded)}")
    {:noreply, port}
  end

  ######################
  ### PRIVATE FUNCTIONS
  ######################

  defp send_delimited(port, data) do
    size = String.length(data)
    send_port(port, <<size::32-unsigned>>)
    send_port(port, data)
  end

  defp send_port(port, data), do: send(port, {self(), {:command, data}})
end
