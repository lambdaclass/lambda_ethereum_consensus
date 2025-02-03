defmodule LambdaEthereumConsensus.Libp2pPort do
  @moduledoc """
  A GenServer that allows other elixir processes to send and receive commands to/from
  the LibP2P server in Go.

  Requests are generated with an ID, which is returned when calling. Those IDs appear
  in the responses that might be listened to by other processes.
  """

  use GenServer

  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.Beacon.SyncBlocks
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.P2P.Gossip.BeaconBlock
  alias LambdaEthereumConsensus.P2P.Gossip.BlobSideCar
  alias LambdaEthereumConsensus.P2P.Gossip.OperationsCollector
  alias LambdaEthereumConsensus.P2P.IncomingRequestsHandler
  alias LambdaEthereumConsensus.P2P.Peerbook
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Utils.BitVector
  alias LambdaEthereumConsensus.ValidatorSet
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
  alias Libp2pProto.Response
  alias Libp2pProto.Result
  alias Libp2pProto.ResultMessage
  alias Libp2pProto.SendRequest
  alias Libp2pProto.SendResponse
  alias Libp2pProto.SetHandler
  alias Libp2pProto.SubscribeToTopic
  alias Libp2pProto.Tracer
  alias Libp2pProto.ValidateMessage
  alias Types.EnrForkId
  alias Types.Store

  require Logger

  @port_name Application.app_dir(:lambda_ethereum_consensus, [
               "priv",
               "native",
               "libp2p_port"
             ])

  @default_args [
    listen_addr: [],
    enable_discovery: false,
    discovery_addr: "",
    bootnodes: [],
    initial_enr: %Enr{eth2: <<0::128>>, attnets: <<0::64>>, syncnets: <<0::8>>}
  ]

  @type init_arg ::
          {:genesis_time, Types.uint64()}
          | {:validator_set, ValidatorSet.t()}
          | {:listen_addr, [String.t()]}
          | {:enable_discovery, boolean()}
          | {:discovery_addr, String.t()}
          | {:bootnodes, [String.t()]}
          | {:join_init_topics, boolean()}
          | {:enable_request_handlers, boolean()}

  @type slot_data() :: {Types.uint64(), :first_third | :second_third | :last_third}

  @type node_identity() :: %{
          peer_id: binary(),
          # Pretty-printed version of the peer ID
          pretty_peer_id: String.t(),
          enr: String.t(),
          p2p_addresses: [String.t()],
          discovery_addresses: [String.t()]
        }

  @tick_time 1000
  @sync_delay_millis 15_000
  @head_drift_alert 12

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

  @spec notify_new_head(Types.slot(), Types.root()) :: :ok
  def notify_new_head(slot, head_root) do
    # TODO: This is quick workarround to notify the libp2p port about new heads from within
    # the ForkChoice.recompute_head/1 without moving the validators to the store this
    # allows to deferr that move until we simplify the state and remove duplicates.
    # THIS IS NEEDED BECAUSE FORKCHOICE IS CURRENTLY RUNNING ON LIBP2P PORT.
    # It could be a simple cast in the future if that's not the case anymore.
    send(self(), {:new_head, slot, head_root})
  end

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

  # Sets libp2pport as the Req/Resp handler for the given protocol ID.
  @spec set_handler(String.t(), port()) :: boolean()
  defp set_handler(protocol_id, port) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "set_handler",
      direction: "elixir->"
    })

    c = {:set_handler, %SetHandler{protocol_id: protocol_id}}
    data = Command.encode(%Command{c: c})

    send_data(port, data)
  end

  @doc """
  Adds a LibP2P peer with the given ID and registers the given addresses.
  After TTL nanoseconds, the addresses are removed.
  """
  @spec add_peer(GenServer.server(), binary(), [String.t()], integer()) ::
          :ok | {:error, String.t()}
  def add_peer(pid \\ __MODULE__, id, addrs, ttl) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "add_peer",
      direction: "elixir->"
    })

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
    :telemetry.execute([:port, :message], %{}, %{
      function: "send_request",
      direction: "elixir->"
    })

    from = self()

    GenServer.cast(
      pid,
      {:send_request, peer_id, protocol_id, message,
       fn store, response ->
         send(from, {:response, response})
         {:ok, store}
       end}
    )

    receive_response()
  end

  @doc """
  Sends a request to a peer. The response will be processed by the Libp2p process.
  """
  def send_async_request(pid \\ __MODULE__, peer_id, protocol_id, message, handler) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "send_request",
      direction: "elixir->"
    })

    GenServer.cast(pid, {:send_request, peer_id, protocol_id, message, handler})
  end

  # Sends a response for the request with the given message ID.
  @spec send_response({String.t(), binary()}, port()) :: boolean()
  defp send_response({request_id, response}, port) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "send_response",
      direction: "elixir->"
    })

    c = {:send_response, %SendResponse{request_id: request_id, message: response}}
    data = Command.encode(%Command{c: c})

    send_data(port, data)
  end

  @doc """
  Joins the given topic.
  This does not subscribe to the topic, use `subscribe_to_topic/2` for that.
  """
  @spec join_topic(GenServer.server(), String.t()) :: :ok
  def join_topic(pid \\ __MODULE__, topic_name) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "join_topic",
      direction: "elixir->"
    })

    cast_command(pid, {:join, %JoinTopic{name: topic_name}})
  end

  @doc """
  Publishes a message in the given topic.
  """
  @spec publish(GenServer.server(), String.t(), binary()) :: :ok | {:error, String.t()}
  def publish(pid \\ __MODULE__, topic_name, message) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "publish",
      direction: "elixir->"
    })

    cast_command(pid, {:publish, %Publish{topic: topic_name, message: message}})
  end

  @doc """
  Subscribes to the given topic. After this, messages published to the topic
  will be received by `self()`.
  """
  @spec subscribe_to_topic(GenServer.server(), String.t(), module()) ::
          :ok | {:error, String.t()}
  def subscribe_to_topic(pid \\ __MODULE__, topic_name, module) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "subscribe_to_topic",
      direction: "elixir->"
    })

    GenServer.cast(pid, {:new_subscriber, topic_name, module})

    call_command(pid, {:subscribe, %SubscribeToTopic{name: topic_name}})
  end

  @doc """
  Subscribes to the given topic async, not waiting for a response at the subscribe.
  After this, messages published to the topicwill be received by `self()`.
  """
  @spec async_subscribe_to_topic(GenServer.server(), String.t(), module()) ::
          :ok | {:error, String.t()}
  def async_subscribe_to_topic(pid \\ __MODULE__, topic_name, module) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "async_subscribe_to_topic",
      direction: "elixir->"
    })

    GenServer.cast(pid, {:new_subscriber, topic_name, module})

    cast_command(pid, {:subscribe, %SubscribeToTopic{name: topic_name}})
  end

  @doc """
  Returns the next gossipsub message received by the server for subscribed topics
  on the current process. If there are none, it waits for one.
  """
  @spec receive_gossip() :: {String.t(), binary(), binary()}
  def receive_gossip() do
    receive do
      {:gossipsub, {_topic_name, _msg_id, _message} = m} -> m
    end
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

    cast_command(
      pid,
      {:validate_message, %ValidateMessage{msg_id: msg_id, result: result}}
    )
  end

  @doc """
  Updates the "eth2", "attnets", and "syncnets" ENR entries for the node.
  """
  @spec update_enr(GenServer.server(), Types.EnrForkId.t(), BitVector.t(), BitVector.t()) ::
          :ok
  def update_enr(pid \\ __MODULE__, enr_fork_id, attnets_bv, syncnets_bv) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "update_enr",
      direction: "elixir->"
    })

    # TODO: maybe move encoding to caller
    enr = encode_enr(enr_fork_id, attnets_bv, syncnets_bv)
    cast_command(pid, {:update_enr, enr})
  end

  @spec get_keystores() :: list(Keystore.t())
  def get_keystores(), do: GenServer.call(__MODULE__, :get_keystores)

  @spec delete_validator(Bls.pubkey()) :: :ok | {:error, String.t()}
  def delete_validator(pubkey), do: GenServer.call(__MODULE__, {:delete_validator, pubkey})

  @spec add_validator(Keystore.t()) :: :ok
  def add_validator(keystore), do: GenServer.call(__MODULE__, {:add_validator, keystore})

  @spec join_init_topics(port()) :: :ok | {:error, String.t()}
  defp join_init_topics(port) do
    topics = [BeaconBlock.topic()] ++ BlobSideCar.topics()

    topics
    |> Enum.each(fn topic_name ->
      c = {:join, %JoinTopic{name: topic_name}}
      data = Command.encode(%Command{c: c})

      send_data(port, data)

      :telemetry.execute([:port, :message], %{}, %{
        function: "join_topic",
        direction: "elixir->"
      })
    end)

    OperationsCollector.init()
  end

  @spec enable_request_handlers(port()) :: :ok | {:error, String.t()}
  defp enable_request_handlers(port) do
    IncomingRequestsHandler.protocol_ids()
    |> Enum.each(fn protocol_id -> set_handler(protocol_id, port) end)
  end

  @doc """
  This function is only used by checkpoint sync to notify of new manually downloaded blocks
  and it should not be related to other manual block downloads or gossip blocks.
  """
  def notify_blocks_downloaded(pid \\ __MODULE__, range, blocks) do
    GenServer.cast(pid, {:add_blocks, range, blocks})
  end

  def notify_block_download_failed(pid \\ __MODULE__, range, reason) do
    GenServer.cast(pid, {:error_downloading_chunk, range, reason})
  end

  @doc """
  Returns the current sync status.
  """
  @spec sync_status(pid | atom()) :: %{
          syncing?: boolean(),
          optimistic?: boolean(),
          el_offline?: boolean(),
          head_slot: Types.slot(),
          sync_distance: non_neg_integer(),
          blocks_remaining: non_neg_integer()
        }
  def sync_status(pid \\ __MODULE__) do
    GenServer.call(pid, :sync_status)
  end

  ########################
  ### GenServer Callbacks
  ########################

  @impl GenServer
  def init(args) do
    {genesis_time, args} = Keyword.pop!(args, :genesis_time)
    {validator_set, args} = Keyword.pop(args, :validator_set, %{})
    {join_init_topics, args} = Keyword.pop(args, :join_init_topics, false)
    {enable_request_handlers, args} = Keyword.pop(args, :enable_request_handlers, false)
    {store, args} = Keyword.pop!(args, :store)

    port = Port.open({:spawn, @port_name}, [:binary, {:packet, 4}, :exit_status])

    current_version = ForkChoice.get_fork_version()

    ([initial_enr: compute_initial_enr(current_version)] ++ args)
    |> parse_args()
    |> InitArgs.encode()
    |> then(&send_data(port, &1))

    if join_init_topics, do: join_init_topics(port)
    if enable_request_handlers, do: enable_request_handlers(port)

    Peerbook.init()
    Process.send_after(self(), :sync_blocks, @sync_delay_millis)

    Logger.info(
      "[Optimistic Sync] Waiting #{@sync_delay_millis / 1000} seconds to discover some peers before requesting blocks."
    )

    schedule_next_tick()

    {:ok,
     %{
       genesis_time: genesis_time,
       validator_set: validator_set,
       slot_data: nil,
       port: port,
       subscribers: %{},
       requests: %{},
       store: store,
       syncing: true
     }, {:continue, :check_pending_blocks}}
  end

  # There may be pending blocks from a prior execution, regardless of the optimistic sync
  # state. We should run a process_blocks round. If no pending blocks are available, this
  # call is a noop.
  @impl GenServer
  def handle_continue(:check_pending_blocks, state) do
    {:noreply, update_in(state.store, &PendingBlocks.process_blocks/1)}
  end

  @impl GenServer
  def handle_cast({:new_subscriber, topic, module}, state) do
    {:noreply, add_subscriber(state, topic, module)}
  end

  @impl GenServer
  def handle_cast({:send, data}, %{port: port} = state) do
    send_data(port, data)
    {:noreply, state}
  end

  def handle_cast(
        {:send_request, peer_id, protocol_id, message, handler},
        %{
          requests: requests,
          port: port
        } = state
      ) do
    {new_requests, handler_id} = add_response_handler(requests, handler)

    send_request = %SendRequest{
      id: peer_id,
      protocol_id: protocol_id,
      message: message,
      request_id: handler_id
    }

    command = %Command{c: {:send_request, send_request}}

    send_data(port, Command.encode(command))
    {:noreply, state |> Map.put(:requests, new_requests)}
  end

  @impl GenServer
  def handle_cast({:add_blocks, {first_slot, last_slot}, blocks}, state) do
    n_blocks = length(blocks)
    missing = last_slot - first_slot + 1 - n_blocks

    Logger.info(
      "[Optimistic Sync] Range #{first_slot} - #{last_slot} downloaded successfully, with #{n_blocks} blocks and #{missing} missing."
    )

    new_store =
      Enum.reduce(blocks, state.store, fn block, store ->
        PendingBlocks.add_block(store, block)
      end)

    new_state =
      state
      |> Map.put(:store, new_store)
      |> Map.update!(:blocks_remaining, fn n -> n - n_blocks - missing end)
      |> subscribe_if_no_blocks()

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:error_downloading_chunk, range, reason}, state) do
    Logger.error(
      "[Optimistic Sync] Failed to download the block range #{inspect(range)}, no retries left. Reason: #{inspect(reason)}"
    )

    # TODO: kill the genserver or retry sync all together.
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:on_tick, state) do
    schedule_next_tick()
    time = :os.system_time(:second)

    {:noreply, on_tick(time, state)}
  end

  @impl GenServer
  def handle_info(:sync_blocks, %{store: store} = state) do
    blocks_to_download = SyncBlocks.run(store)

    new_state =
      state |> Map.put(:blocks_remaining, blocks_to_download) |> subscribe_if_no_blocks()

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:new_head, slot, head_root}, %{validator_set: validator_set} = state) do
    updated_validator_set =
      ValidatorSet.notify_head(validator_set, slot, head_root)

    {:noreply, %{state | validator_set: updated_validator_set}}
  end

  @impl GenServer
  def handle_info({_port, {:data, data}}, state) do
    %Notification{n: {_, payload}} = Notification.decode(data)
    {:noreply, handle_notification(payload, state)}
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

  @impl GenServer
  def handle_call(:get_keystores, _from, %{validator_set: validator_set} = state),
    do: {:reply, ValidatorSet.get_keystores(validator_set), state}

  @impl GenServer
  def handle_call({:delete_validator, pubkey}, _from, %{validator_set: validator_set} = state) do
    case ValidatorSet.remove_validator(validator_set, pubkey) do
      {:ok, validator_set} ->
        Logger.warning("[Libp2pPort] Deleted validator with pubkey #{inspect(pubkey)}.")

        {:reply, :ok, %{state | validator_set: validator_set}}

      {:error, :validator_not_found} ->
        {:reply, {:error, "Validator #{inspect(pubkey)} not found."}, state}
    end
  end

  @impl GenServer
  def handle_call({:add_validator, keystore}, _from, %{validator_set: validator_set} = state) do
    # TODO (#1263): handle 0 validators
    validator_set = ValidatorSet.add_validator(validator_set, keystore)

    Logger.warning("[Libp2pPort] Added validator #{keystore.pubkey} to the set.")

    {:reply, :ok, %{state | validator_set: validator_set}}
  end

  @impl GenServer
  def handle_call(
        :sync_status,
        _from,
        %{syncing: syncing?, store: %Types.Store{} = store} = state
      ) do
    # TODO: (#1325) This is not the final implementation, we are lacking the el check,
    # this is just in place for start using assertoor.
    head_slot = store.head_slot
    current_slot = ForkChoice.get_current_slot(store)
    distance = current_slot - head_slot

    result = %{
      syncing?: syncing?,
      optimistic?: syncing?,
      el_offline?: false,
      head_slot: store.head_slot,
      sync_distance: distance,
      blocks_remaining: Map.get(state, :blocks_remaining)
    }

    {:reply, result, state}
  end

  ######################
  ### PRIVATE FUNCTIONS
  ######################

  defp handle_notification(%GossipSub{} = gs, %{subscribers: subscribers} = state) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "gossipsub",
      direction: "->elixir"
    })

    new_store =
      case Map.fetch(subscribers, gs.topic) do
        {:ok, module} ->
          Metrics.handler_span("gossip_handler", gs.topic, fn ->
            module.handle_gossip_message(state.store, gs.topic, gs.msg_id, gs.message)
          end)

        :error ->
          Logger.error("[Gossip] Received gossip from unknown topic: #{gs.topic}.")
          state.store
      end

    Map.put(state, :store, new_store)
  end

  defp handle_notification(
         %Request{
           protocol_id: protocol_id,
           request_id: request_id,
           message: message
         },
         %{port: port} = state
       ) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "request",
      direction: "->elixir"
    })

    case IncomingRequestsHandler.handle(protocol_id, request_id, message) do
      {:ok, response} ->
        send_response(response, port)

      {:error, reason} ->
        Logger.error("[Libp2pPort] Error handling request. Reason: #{inspect(reason)}")
    end

    state
  end

  defp handle_notification(%NewPeer{peer_id: peer_id}, state) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "new peer",
      direction: "->elixir"
    })

    Peerbook.handle_new_peer(peer_id)
    state
  end

  defp handle_notification(%Response{} = response, %{requests: requests, store: store} = state) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "response",
      direction: "->elixir"
    })

    {new_requests, new_store} = handle_response(requests, store, response)
    state |> Map.merge(%{requests: new_requests, store: new_store})
  end

  defp handle_notification(%Result{from: "", result: result}, state) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "result",
      direction: "->elixir"
    })

    # TODO: amount of failures would be a useful metric
    _success_txt = if match?({:ok, _}, result), do: "success", else: "failed"
    state
  end

  defp handle_notification(%Result{from: from, result: result}, state) do
    :telemetry.execute([:port, :message], %{}, %{
      function: "result",
      direction: "->elixir"
    })

    pid = :erlang.binary_to_term(from)
    send(pid, {:response, result})
    state
  end

  defp handle_notification(%Tracer{t: notification}, state) do
    Metrics.tracer(notification)
    state
  end

  defp parse_args(args) do
    args
    |> Keyword.validate!(@default_args)
    |> then(&struct!(InitArgs, &1))
  end

  @spec send_data(port(), iodata()) :: boolean()
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
      {:response, {:node_identity, identity}} ->
        identity

      {:response, {res, %ResultMessage{message: []}}} ->
        res

      {:response, {res, %ResultMessage{message: message}}} ->
        [res | message] |> List.to_tuple()

      {:response, {res, response}} ->
        {res, response}
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

  defp add_subscriber(state, topic, module) do
    update_in(state.subscribers, fn
      subscribers -> Map.put(subscribers, topic, module)
    end)
  end

  defp topics_for_module(module) do
    Enum.map(module.topics(), fn topic -> {module, topic} end)
  end

  defp subscribe_if_no_blocks(state) do
    if state.blocks_remaining > 0 do
      Logger.info("[Optimistic Sync] Blocks remaining: #{state.blocks_remaining}")
      state
    else
      Logger.info("[Optimistic Sync] Sync completed. Subscribing to gossip topics.")
      subscribe_to_gossip_topics(state)
    end
  end

  defp subscribe_to_gossip_topics(state) do
    [
      LambdaEthereumConsensus.P2P.Gossip.BeaconBlock,
      LambdaEthereumConsensus.P2P.Gossip.BlobSideCar,
      LambdaEthereumConsensus.P2P.Gossip.OperationsCollector
    ]
    |> Enum.flat_map(&topics_for_module/1)
    |> Enum.reduce(state, fn {module, topic}, state ->
      command = %Command{c: {:subscribe, %SubscribeToTopic{name: topic}}}
      send_data(state.port, Command.encode(command))
      add_subscriber(state, topic, module)
    end)
  end

  defp on_tick(time, %{genesis_time: genesis_time} = state) when time < genesis_time, do: state

  defp on_tick(time, %{genesis_time: genesis_time, slot_data: slot_data} = state) do
    # TODO: we probably want to remove this (ForkChoice.on_tick) from here, but we keep it
    # here to have this serialized with respect to the other fork choice store modifications.
    new_store = ForkChoice.on_tick(state.store, time)

    new_slot_data = compute_slot(genesis_time, time)

    updated_state =
      if slot_data == new_slot_data do
        state
      else
        updated_validator_set =
          ValidatorSet.notify_tick(state.validator_set, new_slot_data)

        %{state | slot_data: new_slot_data, validator_set: updated_validator_set}
      end

    maybe_log_new_slot(slot_data, new_slot_data)

    updated_state
    |> Map.put(:store, new_store)
    |> update_syncing_status(new_slot_data, new_store)
  end

  defp update_syncing_status(%{syncing: false} = state, {slot, _third}, %Types.Store{
         head_slot: head_slot
       })
       when slot - head_slot >= @head_drift_alert do
    Logger.error("[Libp2p] Head slot drifted by #{slot - head_slot} slots.")

    # TODO: (#1194) This is a temporary fix to avoid the drift alert to be triggered and the resync to kick in
    # when the node is not fully synced. We should have a better way to handle this.
    Process.send_after(self(), :sync_blocks, 500)

    %{state | syncing: true}
  end

  defp update_syncing_status(
         %{syncing: true, blocks_remaining: 0} = state,
         {slot, _third},
         %Types.Store{head_slot: head_slot}
       )
       when slot - head_slot == 0,
       do: %{state | syncing: false}

  defp update_syncing_status(state, _slot_data, _), do: state

  defp schedule_next_tick() do
    # For millisecond precision
    time_to_next_tick = @tick_time - rem(:os.system_time(:millisecond), @tick_time)
    Process.send_after(__MODULE__, :on_tick, time_to_next_tick)
  end

  defp compute_slot(genesis_time, time) do
    # TODO: This was copied as it is from the Clock, slot calculations are spread
    # across modules, we should probably centralize them.
    elapsed_time = time - genesis_time

    slot_thirds = div(elapsed_time * 3, ChainSpec.get("SECONDS_PER_SLOT"))
    slot = div(slot_thirds, 3)

    slot_third =
      case rem(slot_thirds, 3) do
        0 -> :first_third
        1 -> :second_third
        2 -> :last_third
      end

    {slot, slot_third}
  end

  defp add_response_handler(requests, handler) do
    id = UUID.uuid4()
    {Map.put(requests, id, handler), id}
  end

  # Handles a request using handler_id. The handler will be popped from the
  # requests map.
  #
  # Returns a {status, requests} tuple where:
  # - status is :ok if it was handled or :unhandled if the id didn't correspond to a saved handler.
  # - requests is the modified requests object with the handler removed.
  defp handle_response(requests, store, response) do
    case Map.pop(requests, response.id) do
      {nil, new_requests} ->
        Logger.error("Unhandled response with id: #{response.id}. Message: #{response.message}")
        {new_requests, store}

      {handler, new_requests} ->
        success = if response.success, do: :ok, else: :error

        case handler.(store, {success, response.message}) do
          {:ok, %Store{} = new_store} ->
            {new_requests, new_store}

          {:error, reason} ->
            Logger.warning("Handling response failed with reason: #{reason}")
            {new_requests, store}
        end
    end
  end

  defp maybe_log_new_slot({slot, _third}, {slot, _another_third}), do: :ok

  defp maybe_log_new_slot({_prev_slot, _thrid}, {slot, :first_third}) do
    # TODO: It used :sync, :store as the slot event in the old Clock, double-check.
    :telemetry.execute([:sync, :store], %{slot: slot})
    Logger.info("[Libp2p] Slot transition", slot: slot)
  end

  defp maybe_log_new_slot(_, _), do: :ok
end
