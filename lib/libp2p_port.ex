defmodule LambdaEthereumConsensus.Libp2pPort do
  @moduledoc """
  A GenServer that allows other elixir processes to send and receive commands to/from
  the LibP2P server in Go. For now, it only supports subscribing and unsubscribing from
  topics.

  Requests are generated with an ID, which is returned when calling. Those IDs appear
  in the responses that might be listened to by other processes.
  """

  use GenServer

  alias Libp2pProto.{
    AddPeer,
    Command,
    GetId,
    GossipSub,
    InitArgs,
    Notification,
    Request,
    Result,
    SendRequest,
    SendResponse,
    SetHandler,
    SubscribeToTopic,
    UnsubscribeFromTopic
  }

  require Logger

  @port_name "priv/native/libp2p_port"

  @default_args [
    listen_addr: [],
    enable_discovery: false,
    discovery_addr: "",
    bootnodes: []
  ]

  @type init_arg ::
          {:listen_addr, String.t()}
          | {:enable_discovery, boolean()}
          | {:discovery_addr, String.t()}
          | {:bootnodes, [String.t()]}

  ######################
  ### API
  ######################

  @doc """
  Starts the Port with the given options. `@default_args` specifies default
  values for each of the options.

  ## Options

    * `:opts` - a Keyword list of options to pass onto the GenServer.
      Defaults to `[name: __MODULE__]`.

    * `:listen_addr` - the address to listen on.
    * `:enable_discovery` - boolean that specifies if the discovery service
      should be started.
    * `:discovery_addr` - the address used by the discovery service.
    * `:bootnodes` - a list of bootnodes to use for discovery.
  """
  @spec start_link([{:opts, GenServer.options()} | init_arg()]) :: GenServer.on_start()
  def start_link(init_args) do
    {opts, args} = Keyword.pop(init_args, :opts, name: __MODULE__)
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc """
  Gets the unique ID of the LibP2P node. This ID is used by peers to
  identify and connect to it.
  """
  @spec get_id(GenServer.server()) :: binary()
  def get_id(pid \\ __MODULE__) do
    {:ok, id} = call_command(pid, {:get_id, %GetId{}})
    id
  end

  @doc """
  Sets a Req/Resp handler for the given protocol ID. After this call,
  peer requests are sent to the current process' mailbox. To handle them,
  use `handle_request/0`.
  """
  @spec set_handler(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def set_handler(pid \\ __MODULE__, protocol_id) do
    call_command(pid, {:set_handler, %SetHandler{protocol_id: protocol_id}})
  end

  @doc """
  Adds a LibP2P peer with the given ID and registers the given addresses.
  After TTL nanoseconds, the addresses are removed.
  """
  @spec add_peer(GenServer.server(), binary(), [String.t()], integer()) ::
          :ok | {:error, String.t()}
  def add_peer(pid \\ __MODULE__, id, addrs, ttl) do
    c = %AddPeer{id: id, addrs: addrs, ttl: ttl}
    call_command(pid, {:add_peer, c})
  end

  @doc """
  Sends a request and receives a response. The request is sent
  to the given peer and protocol.
  """
  @spec send_request(GenServer.server(), binary(), String.t(), binary()) ::
          {:ok, binary()} | {:error, String.t()}
  def send_request(pid \\ __MODULE__, peer_id, protocol_id, message) do
    c = %SendRequest{id: peer_id, protocol_id: protocol_id, message: message}
    call_command(pid, {:send_request, c})
  end

  @doc """
  Returns the next request received by the server for registered handlers
  on the current process. If there are no requests, it waits for one.
  """
  @spec handle_request() :: {String.t(), String.t(), binary()}
  def handle_request do
    receive do
      {:request, {_protocol_id, _message_id, _message} = request} -> request
    end
  end

  @doc """
  Sends a response for the request with the given message ID.
  """
  @spec send_response(GenServer.server(), String.t(), binary()) ::
          :ok | {:error, String.t()}
  def send_response(pid \\ __MODULE__, message_id, response) do
    c = %SendResponse{message_id: message_id, message: response}
    call_command(pid, {:send_response, c})
  end

  @doc """
  Subscribes to the given topic. After this, messages published to the topic
  will be received by `self()`.
  """
  @spec subscribe_to_topic(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def subscribe_to_topic(pid \\ __MODULE__, topic_name) do
    call_command(pid, {:subscribe, %SubscribeToTopic{name: topic_name}})
  end

  @doc """
  Returns the next gossipsub message received by the server for subscribed topics
  on the current process. If there are none, it waits for one.
  """
  @spec receive_gossip() :: {String.t(), binary()}
  def receive_gossip do
    receive do
      {:gossipsub, {_topic_name, _message} = m} -> m
    end
  end

  @doc """
  Unsubscribes from the given topic.
  """
  @spec unsubscribe_from_topic(GenServer.server(), String.t()) :: :ok
  def unsubscribe_from_topic(pid \\ __MODULE__, topic_name) do
    cast_command(pid, {:unsubscribe, %UnsubscribeFromTopic{name: topic_name}})
  end

  ########################
  ### GenServer Callbacks
  ########################

  @impl GenServer
  def init(args) do
    port = Port.open({:spawn, @port_name}, [:binary, {:packet, 4}, :exit_status])

    args
    |> parse_args()
    |> InitArgs.encode()
    |> then(&send_data(port, &1))

    {:ok, port}
  end

  @impl GenServer
  def handle_cast({:send, data}, port) do
    send_data(port, data)
    {:noreply, port}
  end

  @impl GenServer
  def handle_info({port, {:data, data}}, port) do
    %Notification{n: {_, payload}} = Notification.decode(data)
    handle_notification(payload)

    {:noreply, port}
  end

  @impl GenServer
  def handle_info({port, {:exit_status, status}}, port),
    do: Process.exit(self(), status)

  @impl GenServer
  def handle_info(other, port) do
    Logger.error(inspect(other))
    {:noreply, port}
  end

  ######################
  ### PRIVATE FUNCTIONS
  ######################

  defp handle_notification(%GossipSub{topic: topic, handler: handler, message: message}) do
    handler_pid = :erlang.binary_to_term(handler)
    send(handler_pid, {:gossipsub, {topic, message}})
  end

  defp handle_notification(%Request{
         protocol_id: protocol_id,
         handler: handler,
         message_id: message_id,
         message: message
       }) do
    handler_pid = :erlang.binary_to_term(handler)
    send(handler_pid, {:request, {protocol_id, message_id, message}})
  end

  defp handle_notification(%Result{from: from, success: success, message: message}) do
    case from do
      nil ->
        success_txt = if success, do: "success", else: "failed"
        Logger.info("[Result] #{success_txt}: #{message}")

      from ->
        pid = :erlang.binary_to_term(from)
        send(pid, {:response, {success, message}})
    end
  end

  defp parse_args(args) do
    args
    |> Keyword.validate!(@default_args)
    |> then(&struct!(InitArgs, &1))
  end

  defp send_data(port, data), do: Port.command(port, data)

  defp send_protobuf(pid, %mod{} = protobuf) do
    data = mod.encode(protobuf)
    GenServer.cast(pid, {:send, data})
  end

  defp cast_command(pid, c) do
    send_protobuf(pid, %Command{c: c})
  end

  defp call_command(pid, c) do
    self_serialized = :erlang.term_to_binary(self())
    send_protobuf(pid, %Command{from: self_serialized, c: c})
    receive_response()
  end

  defp receive_response do
    receive do
      {:response, {true, ""}} -> :ok
      {:response, {true, message}} -> {:ok, message}
      {:response, {false, message}} -> {:error, message}
    end
  end
end
