defmodule Libp2p do
  @moduledoc """
  Documentation for `Libp2p`.
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
  An error returned by this module.
  """
  @type error :: {:error, binary}

  @doc """
  The ttl for a "permanent address" (e.g. bootstrap nodes).
  """
  @spec ttl_permanent_addr :: integer
  def ttl_permanent_addr, do: 2 ** 63 - 1

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
  Returns an `Option` that can be passed to `host_new`
  as an argument to configures libp2p to listen on the
  given (unparsed) addresses.
  """
  @spec listen_addr_strings(binary) :: {:ok, option} | error
  def listen_addr_strings(_addr),
    do: :erlang.nif_error(:not_implemented)

  @doc """
  Creates a new `Stream` connected to the
  peer with the given id, using the protocol with given id.
  """
  @spec host_new_stream(host, peer_id, binary) :: {:ok, stream} | error
  def host_new_stream(_host, _peer_id, _protocol_id),
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
end
