defmodule LambdaEthereumConsensus.Libp2pPort do
  @moduledoc """
  A GenServer that allows other elixir processes to send and receive commands to/from
  the LibP2P server in Go.

  Requests are generated with an ID, which is returned when calling. Those IDs appear
  in the responses that might be listened to by other processes.
  """

  use GenServer

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Utils.BitVector
  alias Types.EnrForkId

  alias Libp2pProto.AddPeer
  alias Libp2pProto.Command
  alias Libp2pProto.Enr
  alias Libp2pProto.GetNodeIdentity
  alias Libp2pProto.GossipSub
  alias Libp2pProto.InitArgs
  alias Libp2pProto.JoinTopic
  alias Libp2pProto.LeaveTopic
  alias Libp2pProto.NewPeer
  alias Libp2pProto.Notification
  alias Libp2pProto.Publish
  alias Libp2pProto.Request
  alias Libp2pProto.Result
  alias Libp2pProto.ResultMessage
  alias Libp2pProto.SendRequest
  alias Libp2pProto.SendResponse
  alias Libp2pProto.SetHandler
  alias Libp2pProto.SubscribeToTopic
  alias Libp2pProto.Tracer
  alias Libp2pProto.ValidateMessage

  require Logger

  @port_name Application.app_dir(:lambda_ethereum_consensus, ["priv", "native", "libp2p_port"])

  @default_args [
    listen_addr: [],
    enable_discovery: false,
    discovery_addr: "",
    bootnodes: [],
    initial_enr: %Enr{eth2: <<0::128>>, attnets: <<0::64>>, syncnets: <<0::8>>}
  ]

  @type init_arg ::
          {:listen_addr, [String.t()]}
          | {:enable_discovery, boolean()}
          | {:discovery_addr, String.t()}
          | {:bootnodes, [String.t()]}
          | {:new_peer_handler, pid()}

  ######################
  ### API
  ######################

  @doc """
  Starts the Port with the given options. `@default_args` specifies default
  values for each of the options.

  ## Options

    * `:opts` - a Keyword list of options to pass onto the GenServer.
      Defaults to `[name: __MODULE__]`.

    * `:listen_addr` - the addresses to listen on, in `Multiaddr` format.
    * `:enable_discovery` - boolean that specifies if the discovery service
      should be started.
    * `:discovery_addr` - the address used by the discovery service, in `host:port` format.
    * `:bootnodes` - a list of bootnodes to use for discovery.
  """
  @spec start_link([{:opts, GenServer.options()} | init_arg()]) :: GenServer.on_start()
  def start_link(init_args) do
    {opts, args} = Keyword.pop(init_args, :opts, name: __MODULE__)
    GenServer.start_link(__MODULE__, args, opts)
  end

  @type node_identity() :: %{
          peer_id: binary(),
          # Pretty-printed version of the peer ID
          pretty_peer_id: String.t(),
          enr: String.t(),
          p2p_addresses: [String.t()],
          discovery_addresses: [String.t()]
        }

  @doc """
  Retrieves identity info from the underlying LibP2P node.
  """
  @spec get_node_identity(GenServer.server()) :: node_identity()
  def get_node_identity(pid \\ __MODULE__) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "get_node_identity",
      direction: "elixir->"
    })

    call_command(pid, {:get_node_identity, %GetNodeIdentity{}})
    |> Map.take([:peer_id, :pretty_peer_id, :enr, :p2p_addresses, :discovery_addresses])
  end

  @doc """
  Sets a Req/Resp handler for the given protocol ID. After this call,
  peer requests are sent to the current process' mailbox. To handle them,
  use `handle_request/0`.
  """
  @spec set_handler(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def set_handler(pid \\ __MODULE__, protocol_id) do
    :telemetry.execute([:port, :message], %{}, %{function: "set_handler", direction: "elixir->"})
    call_command(pid, {:set_handler, %SetHandler{protocol_id: protocol_id}})
  end

  @doc """
  Adds a LibP2P peer with the given ID and registers the given addresses.
  After TTL nanoseconds, the addresses are removed.
  """
  @spec add_peer(GenServer.server(), binary(), [String.t()], integer()) ::
          :ok | {:error, String.t()}
  def add_peer(pid \\ __MODULE__, id, addrs, ttl) do
    :telemetry.execute([:port, :message], %{}, %{function: "add_peer", direction: "elixir->"})
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
    :telemetry.execute([:port, :message], %{}, %{function: "send_request", direction: "elixir->"})
    c = %SendRequest{id: peer_id, protocol_id: protocol_id, message: message}
    call_command(pid, {:send_request, c})
  end

  @doc """
  Returns the next request received by the server for registered handlers
  on the current process. If there are no requests, it waits for one.
  """
  @spec handle_request() :: {String.t(), String.t(), binary()}
  def handle_request() do
    receive do
      {:request, {_protocol_id, _message_id, _message} = request} -> request
    end
  end

  @doc """
  Sends a response for the request with the given message ID.
  """
  @spec send_response(GenServer.server(), String.t(), binary()) ::
          :ok | {:error, String.t()}
  def send_response(pid \\ __MODULE__, request_id, response) do
    :telemetry.execute([:port, :message], %{}, %{function: "send_response", direction: "elixir->"})

    c = %SendResponse{request_id: request_id, message: response}
    call_command(pid, {:send_response, c})
  end

  @doc """
  Joins the given topic.
  This does not subscribe to the topic, use `subscribe_to_topic/2` for that.
  """
  @spec join_topic(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def join_topic(pid \\ __MODULE__, topic_name) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "join_topic",
      direction: "elixir->"
    })

    call_command(pid, {:join, %JoinTopic{name: topic_name}})
  end

  @doc """
  Publishes a message in the given topic.
  """
  @spec publish(GenServer.server(), String.t(), binary()) :: :ok | {:error, String.t()}
  def publish(pid \\ __MODULE__, topic_name, message) do
    :telemetry.execute([:port, :message], %{}, %{function: "publish", direction: "elixir->"})
    call_command(pid, {:publish, %Publish{topic: topic_name, message: message}})
  end

  @doc """
  Subscribes to the given topic. After this, messages published to the topic
  will be received by `self()`.
  """
  @spec subscribe_to_topic(GenServer.server(), String.t(), atom()) :: :ok | {:error, String.t()}
  def subscribe_to_topic(pid \\ __MODULE__, topic_name, module) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "subscribe_to_topic",
      direction: "elixir->"
    })

    GenServer.cast(__MODULE__, {:new_subscriptor, String.to_atom(topic_name), module})

    call_command(pid, {:subscribe, %SubscribeToTopic{name: topic_name}})
  end

  @doc """
  Leaves the given topic, unsubscribing if possible.
  """
  @spec leave_topic(GenServer.server(), String.t()) :: :ok
  def leave_topic(pid \\ __MODULE__, topic_name) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "leave_topic",
      direction: "elixir->"
    })

    cast_command(pid, {:leave, %LeaveTopic{name: topic_name}})
  end

  @doc """
  Sets the receiver of new peer notifications.
  If `nil`, notifications are disabled.
  """
  @spec set_new_peer_handler(GenServer.server(), pid() | nil) :: :ok
  def set_new_peer_handler(pid \\ __MODULE__, handler) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "set_new_peer_handler",
      direction: "elixir->"
    })

    GenServer.cast(pid, {:set_new_peer_handler, handler})
  end

  @doc """
  Marks the message with a validation result. The result can be `:accept`, `:reject` or `:ignore`:
    * `:accept` - the message is valid and should be propagated.
    * `:reject` - the message is invalid, mustn't be propagated, and its sender should be penalized.
    * `:ignore` - the message is invalid, mustn't be propagated, but its sender shouldn't be penalized.
  """
  @spec validate_message(GenServer.server(), binary(), :accept | :reject | :ignore) :: :ok
  def validate_message(pid \\ __MODULE__, msg_id, result) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "validate_message",
      direction: "elixir->"
    })

    cast_command(pid, {:validate_message, %ValidateMessage{msg_id: msg_id, result: result}})
  end

  @doc """
  Updates the "eth2", "attnets", and "syncnets" ENR entries for the node.
  """
  @spec update_enr(GenServer.server(), Types.EnrForkId.t(), BitVector.t(), BitVector.t()) :: :ok
  def update_enr(pid \\ __MODULE__, enr_fork_id, attnets_bv, syncnets_bv) do
    :telemetry.execute([:port, :message], %{}, %{function: "update_enr", direction: "elixir->"})
    # TODO: maybe move encoding to caller
    enr = encode_enr(enr_fork_id, attnets_bv, syncnets_bv)
    cast_command(pid, {:update_enr, enr})
  end

  ########################
  ### GenServer Callbacks
  ########################

  @impl GenServer
  def init(args) do
    {new_peer_handler, args} = Keyword.pop(args, :new_peer_handler, nil)

    port = Port.open({:spawn, @port_name}, [:binary, {:packet, 4}, :exit_status])

    current_version = BeaconChain.get_fork_version()

    ([initial_enr: compute_initial_enr(current_version)] ++ args)
    |> parse_args()
    |> InitArgs.encode()
    |> then(&send_data(port, &1))

    {:ok, %{port: port, new_peer_handler: new_peer_handler, subscriptors: %{}}}
  end

  @impl GenServer
  def handle_cast({:new_subscriptor, topic, module}, %{subscriptors: subscriptors} = state) do
    new_subscriptors = Map.put(subscriptors, topic, module)
    {:noreply, %{state | subscriptors: new_subscriptors}}
  end

  @impl GenServer
  def handle_cast({:send, data}, %{port: port} = state) do
    send_data(port, data)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:set_new_peer_handler, new_peer_handler}, state) do
    {:noreply, %{state | new_peer_handler: new_peer_handler}}
  end

  @impl GenServer
  def handle_info({_port, {:data, data}}, state) do
    %Notification{n: {_, payload}} = Notification.decode(data)
    handle_notification(payload, state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({_port, {:exit_status, status}}, _state),
    do: Process.exit(self(), status)

  @impl GenServer
  def handle_info(other, state) do
    :telemetry.execute([:port, :message], %{}, %{function: "other", direction: "->elixir"})
    Logger.error(inspect(other))
    {:noreply, state}
  end

  ######################
  ### PRIVATE FUNCTIONS
  ######################

  defp handle_notification(%GossipSub{} = gs, %{subscriptors: subscriptors}) do
    :telemetry.execute([:port, :message], %{}, %{function: "gossipsub", direction: "->elixir"})
    # handler_pid = :erlang.binary_to_term(gs.handler)
    # send(handler_pid, {:gossipsub, {gs.topic, gs.msg_id, gs.message}})
    {:ok, module} = Map.fetch(subscriptors, String.to_atom(gs.topic))
    module.handle_gossip_message(gs.topic, gs.msg_id, gs.message)
  end

  defp handle_notification(
         %Request{
           protocol_id: protocol_id,
           handler: handler,
           request_id: request_id,
           message: message
         },
         _state
       ) do
    :telemetry.execute([:port, :message], %{}, %{function: "request", direction: "->elixir"})
    handler_pid = :erlang.binary_to_term(handler)
    send(handler_pid, {:request, {protocol_id, request_id, message}})
  end

  defp handle_notification(%NewPeer{peer_id: _peer_id}, %{new_peer_handler: nil}), do: :ok

  defp handle_notification(%NewPeer{peer_id: peer_id}, %{new_peer_handler: handler}) do
    :telemetry.execute([:port, :message], %{}, %{function: "new peer", direction: "->elixir"})
    send(handler, {:new_peer, peer_id})
  end

  defp handle_notification(%Result{from: "", result: result}, _state) do
    :telemetry.execute([:port, :message], %{}, %{function: "result", direction: "->elixir"})
    # TODO: amount of failures would be a useful metric
    _success_txt = if match?({:ok, _}, result), do: "success", else: "failed"
  end

  defp handle_notification(%Result{from: from, result: result}, _state) do
    :telemetry.execute([:port, :message], %{}, %{function: "result", direction: "->elixir"})
    pid = :erlang.binary_to_term(from)
    send(pid, {:response, result})
  end

  defp handle_notification(%Tracer{t: {:add_peer, %{}}}, _state) do
    :telemetry.execute([:network, :pubsub_peers], %{}, %{
      result: "add"
    })
  end

  defp handle_notification(%Tracer{t: {:remove_peer, %{}}}, _state) do
    :telemetry.execute([:network, :pubsub_peers], %{}, %{
      result: "remove"
    })
  end

  defp handle_notification(%Tracer{t: {:joined, %{topic: topic}}}, _state) do
    :telemetry.execute([:network, :pubsub_topic_active], %{active: 1}, %{
      topic: get_topic_name(topic)
    })
  end

  defp handle_notification(%Tracer{t: {:left, %{topic: topic}}}, _state) do
    :telemetry.execute([:network, :pubsub_topic_active], %{active: -1}, %{
      topic: get_topic_name(topic)
    })
  end

  defp handle_notification(%Tracer{t: {:grafted, %{topic: topic}}}, _state) do
    :telemetry.execute([:network, :pubsub_topics_graft], %{}, %{topic: get_topic_name(topic)})
  end

  defp handle_notification(%Tracer{t: {:pruned, %{topic: topic}}}, _state) do
    :telemetry.execute([:network, :pubsub_topics_prune], %{}, %{topic: get_topic_name(topic)})
  end

  defp handle_notification(%Tracer{t: {:deliver_message, %{topic: topic}}}, _state) do
    :telemetry.execute([:network, :pubsub_topics_deliver_message], %{}, %{
      topic: get_topic_name(topic)
    })
  end

  defp handle_notification(%Tracer{t: {:duplicate_message, %{topic: topic}}}, _state) do
    :telemetry.execute([:network, :pubsub_topics_duplicate_message], %{}, %{
      topic: get_topic_name(topic)
    })
  end

  defp handle_notification(%Tracer{t: {:reject_message, %{topic: topic}}}, _state) do
    :telemetry.execute([:network, :pubsub_topics_reject_message], %{}, %{
      topic: get_topic_name(topic)
    })
  end

  defp handle_notification(%Tracer{t: {:un_deliverable_message, %{topic: topic}}}, _state) do
    :telemetry.execute([:network, :pubsub_topics_un_deliverable_message], %{}, %{
      topic: get_topic_name(topic)
    })
  end

  defp handle_notification(%Tracer{t: {:validate_message, %{topic: topic}}}, _state) do
    :telemetry.execute([:network, :pubsub_topics_validate_message], %{}, %{
      topic: get_topic_name(topic)
    })
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

  defp receive_response() do
    receive do
      {:response, {:node_identity, identity}} -> identity
      {:response, {res, %ResultMessage{message: []}}} -> res
      {:response, {res, %ResultMessage{message: message}}} -> [res | message] |> List.to_tuple()
    end
  end

  defp get_topic_name(topic) do
    case topic |> String.split("/") |> Enum.fetch(3) do
      {:ok, name} -> name
      :error -> topic
    end
  end

  defp encode_enr(enr_fork_id, attnets_bv, syncnets_bv) do
    {:ok, eth2} = SszEx.encode(enr_fork_id, Types.EnrForkId)

    {:ok, attnets} =
      SszEx.encode(attnets_bv, {:bitvector, ChainSpec.get("ATTESTATION_SUBNET_COUNT")})

    {:ok, syncnets} =
      SszEx.encode(syncnets_bv, {:bitvector, Constants.sync_committee_subnet_count()})

    %Enr{eth2: eth2, attnets: attnets, syncnets: syncnets}
  end

  defp compute_initial_enr(current_version) do
    fork_digest =
      Misc.compute_fork_digest(current_version, ChainSpec.get_genesis_validators_root())

    attnets = BitVector.new(ChainSpec.get("ATTESTATION_SUBNET_COUNT"))
    syncnets = BitVector.new(Constants.sync_committee_subnet_count())

    %EnrForkId{
      fork_digest: fork_digest,
      next_fork_version: current_version,
      next_fork_epoch: Constants.far_future_epoch()
    }
    |> encode_enr(attnets, syncnets)
  end
end
