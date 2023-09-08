defmodule Libp2p do
  @moduledoc """
  Bindings for P2P network primitives.
  """

  @on_load :load_nifs

  def load_nifs do
    dir = :code.priv_dir(:lambda_ethereum_consensus)
    :erlang.load_nif(dir ++ ~c"/native/libp2p_nif", 0)
  end

  @typedoc """
  A handle to a Go resource.
  """
  @opaque handle :: reference

  @typedoc """
  A handle to a host.Host.
  """
  @opaque host :: handle

  @typedoc """
  A handle to a peerstore.Peerstore.
  """
  @opaque peerstore :: handle

  @typedoc """
  A handle to a peer.ID.
  """
  @opaque peer_id :: handle

  @typedoc """
  A handle to a []multiaddr.MultiAddr.
  """
  @opaque addrs :: handle

  @typedoc """
  A handle to a stream.
  """
  @opaque stream :: handle

  @typedoc """
  A handle to an Option.
  """
  @opaque option :: handle

  @typedoc """
  A handle to a discv5 listener.
  """
  @opaque listener :: handle

  @typedoc """
  A discv5 node iterator.
  """
  @opaque iterator :: handle

  @typedoc """
  A node using discv5.
  """
  @opaque discv5_node :: handle

  @typedoc """
  PubSub handle.
  """
  @opaque pub_sub :: handle

  @typedoc """
  Topic handle.
  """
  @opaque topic :: handle

  @typedoc """
  PubSub topic subscription.
  """
  @opaque subscription :: handle

  @typedoc """
  PubSub message.
  """
  @opaque message :: handle

  @typedoc """
  An error returned by this module.
  """
  @type error :: {:error, binary}

  @doc """
  The ttl for a "permanent address" (e.g. bootstrap nodes).
  """
  @spec ttl_permanent_addr :: integer
  def ttl_permanent_addr, do: 2 ** 63 - 1

  @doc """
  Gets next subscription message.
  """
  @spec next_subscription_message(timeout) :: {:ok, message} | :cancelled | :timeout
  def next_subscription_message(timeout \\ :infinity) do
    receive do
      {:sub, result} -> result
    after
      timeout -> :timeout
    end
  end

  @doc """
  Synchronously connects to the given peer.
  """
  @spec host_connect(host, peer_id) :: :ok | error
  def host_connect(host, peer_id) do
    :ok = _host_connect(host, peer_id)

    receive do
      {:connect, result} -> result
    end
  end

  @doc """
  Returns an `Option` that can be passed to `host_new`
  as an argument to configures libp2p to listen on the
  given (unparsed) addresses.
  """
  @spec listen_addr_strings(binary) :: {:ok, option} | error
  def listen_addr_strings(_addr),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Creates a Host, with the given options.
  """
  @spec host_new(list(option)) :: {:ok, host} | error
  def host_new(_option_list \\ []),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Deletes a Host.
  """
  @spec host_close(host) :: :ok | error
  def host_close(_host),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Sets the stream handler associated to a protocol id.
  """
  @spec host_set_stream_handler(host, binary) :: :ok | error
  def host_set_stream_handler(_host, _protocol_id),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Creates a new `Stream` connected to the
  peer with the given id, using the protocol with given id.
  """
  @spec host_new_stream(host, peer_id, binary) :: {:ok, stream} | error
  def host_new_stream(_host, _peer_id, _protocol_id),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Connects to the given peer asynchronously.
  """
  @spec _host_connect(host, peer_id) :: :ok
  def _host_connect(_host, _peer_id),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Gets the `Peerstore` of the given `Host`.
  """
  @spec host_peerstore(host) :: {:ok, peerstore} | error
  def host_peerstore(_host),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Gets the `ID` of the given `Host`.
  """
  @spec host_id(host) :: {:ok, peer_id} | error
  def host_id(_host),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Gets the addresses of the given `Host`.
  """
  @spec host_addrs(host) :: {:ok, addrs} | error
  def host_addrs(_host),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Adds the addresses of the peer with the given ID to
  the `Peerstore`. The addresses are valid for the given
  TTL.
  """
  @spec peerstore_add_addrs(peerstore, peer_id, addrs, integer) :: :ok | error
  def peerstore_add_addrs(_peerstore, _peer_id, _addrs, _ttl),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Reads bytes from the stream (up to a predefined maximum).
  """
  @spec stream_read(stream) :: {:ok, binary} | error
  def stream_read(_stream),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Writes data into the stream.
  """
  @spec stream_write(stream, binary) :: :ok | error
  def stream_write(_stream, _data),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Closes the stream.
  """
  @spec stream_close(stream) :: :ok | error
  def stream_close(_stream),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Closes the write side of the stream.
  """
  @spec stream_close_write(stream) :: :ok | error
  def stream_close_write(_stream),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Returns the ID of the underlying protocol.
  """
  @spec stream_protocol(stream) :: {:ok, binary} | error
  def stream_protocol(_stream),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Creates a discv5 listener.
  """
  @spec listen_v5(binary, list(binary)) :: {:ok, listener} | error
  def listen_v5(_addr, _bootnodes),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Creates a discv5 nodes iterator for random nodes.
  """
  @spec listener_random_nodes(listener) :: {:ok, iterator} | error
  def listener_random_nodes(_listener),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Moves the iterator to the next node.
  Returns false if there are no more nodes.
  """
  @spec iterator_next(iterator) :: boolean
  def iterator_next(_iterator), do: :erlang.nif_error(:not_implemented)

  @doc """
  Returns the current node.
  WARN: you need to call iterator_next before calling this function!
  """
  @spec iterator_node(iterator) :: {:ok, discv5_node} | error
  def iterator_node(_iterator), do: :erlang.nif_error(:not_implemented)

  @doc """
  Returns the published TCP port of the node, or nil.
  """
  @spec node_tcp(discv5_node) :: integer | nil
  def node_tcp(_node), do: :erlang.nif_error(:not_implemented)

  @doc """
  Returns the multiaddresses of the node.
  """
  @spec node_multiaddr(discv5_node) :: {:ok, addrs} | error
  def node_multiaddr(_node), do: :erlang.nif_error(:not_implemented)

  @doc """
  Returns the ID of the node.
  """
  @spec node_id(discv5_node) :: {:ok, peer_id} | error
  def node_id(_node), do: :erlang.nif_error(:not_implemented)

  @doc """
  Creates a new GossipSub router.
  """
  @spec new_gossip_sub(host) :: {:ok, pub_sub} | error
  def new_gossip_sub(_host), do: :erlang.nif_error(:not_implemented)

  @doc """
  Joins a topic. If the topic was already joined, this will fail.
  """
  @spec pub_sub_join(pub_sub, binary) :: {:ok, topic} | error
  def pub_sub_join(_pubsub, _topic_str), do: :erlang.nif_error(:not_implemented)

  @doc """
  Subscribes to the given topic. After this call, `self()` will start receiving
  messages from the topic. Those can be received via `get_subscription_message/0`.
  """
  @spec topic_subscribe(topic) :: {:ok, subscription} | error
  def topic_subscribe(_topic), do: :erlang.nif_error(:not_implemented)

  @doc """
  Publishes data on the given topic.
  """
  @spec topic_publish(topic, binary) :: :ok | error
  def topic_publish(_topic, _data), do: :erlang.nif_error(:not_implemented)

  @doc """
  Cancels a given subscription.
  """
  @spec subscription_cancel(subscription) :: :ok
  def subscription_cancel(_subscription), do: :erlang.nif_error(:not_implemented)

  @doc """
  Gets the application data from a message.
  """
  @spec message_data(message) :: {:ok, binary} | error
  def message_data(_message), do: :erlang.nif_error(:not_implemented)
end
