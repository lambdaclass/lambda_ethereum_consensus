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

  @type init_arg :: {:listen_addr, String.t()}

  ######################
  ### API
  ######################

  @spec start_link([{:opts, GenServer.options()} | init_arg()]) :: GenServer.on_start()
  def start_link(init_args) do
    opts = Keyword.get(init_args, :opts, name: __MODULE__)
    GenServer.start_link(__MODULE__, init_args, opts)
  end

  @spec get_id(GenServer.server()) :: binary()
  def get_id(pid \\ __MODULE__) do
    self_serialized = :erlang.term_to_binary(self())
    {:ok, id} = call_command(pid, %Command{from: self_serialized, c: {:get_id, %GetId{}}})
    id
  end

  @spec set_handler(String.t()) :: :ok | {:error, String.t()}
  def set_handler(protocol_id), do: set_handler(__MODULE__, protocol_id)

  @spec set_handler(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def set_handler(pid, protocol_id) do
    self_serialized = :erlang.term_to_binary(self())
    c = %SetHandler{protocol_id: protocol_id, handler: self_serialized}
    call_command(pid, %Command{from: self_serialized, c: {:set_handler, c}})
  end

  @spec add_peer(binary(), [String.t()], integer()) ::
          :ok | {:error, String.t()}
  def add_peer(id, addrs, ttl), do: add_peer(__MODULE__, id, addrs, ttl)

  @spec add_peer(GenServer.server(), binary(), [String.t()], integer()) ::
          :ok | {:error, String.t()}
  def add_peer(pid, id, addrs, ttl) do
    self_serialized = :erlang.term_to_binary(self())
    c = %AddPeer{id: id, addrs: addrs, ttl: ttl}
    call_command(pid, %Command{from: self_serialized, c: {:add_peer, c}})
  end

  @spec send_request(binary(), String.t(), binary()) ::
          {:ok, binary()} | {:error, String.t()}
  def send_request(id, protocol_id, message),
    do: send_request(__MODULE__, id, protocol_id, message)

  @spec send_request(GenServer.server(), binary(), String.t(), binary()) ::
          {:ok, binary()} | {:error, String.t()}
  def send_request(pid, id, protocol_id, message) do
    self_serialized = :erlang.term_to_binary(self())
    c = %SendRequest{id: id, protocol_id: protocol_id, message: message}
    call_command(pid, %Command{from: self_serialized, c: {:send_request, c}})
  end

  @spec handle_request() :: {String.t(), String.t(), binary()}
  def handle_request do
    receive do
      {:request, {_protocol_id, _message_id, _message} = request} -> request
    end
  end

  @spec send_response(String.t(), binary()) ::
          :ok | {:error, String.t()}
  def send_response(message_id, response), do: send_response(__MODULE__, message_id, response)

  @spec send_response(GenServer.server(), String.t(), binary()) ::
          :ok | {:error, String.t()}
  def send_response(pid, message_id, response) do
    self_serialized = :erlang.term_to_binary(self())
    c = %SendResponse{message_id: message_id, message: response}
    call_command(pid, %Command{from: self_serialized, c: {:send_response, c}})
  end

  @spec subscribe_to_topic(String.t()) :: :ok
  def subscribe_to_topic(topic_name), do: subscribe_to_topic(__MODULE__, topic_name)

  @spec subscribe_to_topic(GenServer.server(), String.t()) :: :ok
  def subscribe_to_topic(pid, topic_name) do
    cast_command(pid, %Command{
      c: {:subscribe, %SubscribeToTopic{name: topic_name}}
    })
  end

  @spec unsubscribe_from_topic(String.t()) :: :ok
  def unsubscribe_from_topic(topic_name), do: unsubscribe_from_topic(__MODULE__, topic_name)

  @spec unsubscribe_from_topic(GenServer.server(), String.t()) :: :ok
  def unsubscribe_from_topic(pid, topic_name) do
    cast_command(pid, %Command{
      c: {:unsubscribe, %UnsubscribeFromTopic{name: topic_name}}
    })
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
    data
    |> Notification.decode()
    |> handle_notification()

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

  defp handle_notification(%Notification{
         n: {:gossip, %GossipSub{topic: topic, message: message}}
       }) do
    Logger.info("[Topic] #{topic}: #{message}")
  end

  defp handle_notification(%Notification{
         n:
           {:request,
            %Request{
              protocol_id: protocol_id,
              handler: handler,
              message_id: message_id,
              message: message
            }}
       }) do
    handler_pid = :erlang.binary_to_term(handler)
    send(handler_pid, {:request, {protocol_id, message_id, message}})
  end

  defp handle_notification(%Notification{
         n: {:result, %Result{from: from, success: success, message: message}}
       }) do
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
    listen_addr = Keyword.get(args, :listen_addr, [])
    %InitArgs{listen_addr: listen_addr}
  end

  defp send_data(port, data), do: Port.command(port, data)

  defp cast_command(pid, %mod{} = protobuf) do
    data = mod.encode(protobuf)
    GenServer.cast(pid, {:send, data})
  end

  defp call_command(pid, protobuf) do
    cast_command(pid, protobuf)
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
