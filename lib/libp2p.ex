defmodule Libp2p do
  @moduledoc """
  Documentation for `Libp2p`.
  """

  @on_load :load_nifs

  def load_nifs do
    :erlang.load_nif(~c"./libp2p", 0)
  end

  @typedoc """
  A handle to a Go resource.
  """
  @type handle :: integer

  @typedoc """
  A handle to a host.Host.
  """
  @type host :: handle

  @typedoc """
  A handle to a peerstore.Peerstore.
  """
  @type peerstore :: handle

  @typedoc """
  A handle to a peer.ID.
  """
  @type peer_id :: handle

  @typedoc """
  A handle to a []multiaddr.MultiAddr.
  """
  @type addrs :: handle

  @typedoc """
  A handle to a stream.
  """
  @type stream :: handle

  @typedoc """
  A handle to an Option.
  """
  @type option :: handle

  @typedoc """
  An error returned by this module.
  """
  @type error :: {:error, charlist}

  @doc """
  The ttl for a "permanent address" (e.g. bootstrap nodes).
  """
  @spec ttl_permanent_addr :: integer
  def ttl_permanent_addr, do: 2 ** 63 - 1

  @doc """
  Creates a new Host.
  """
  @spec host_new :: {:ok, host} | error
  def host_new() do
    raise "NIF host_new not implemented"
  end

  @doc """
  Deletes a Host.
  """
  @spec host_close(host) :: nil
  def host_close(_host) do
    raise "NIF host_close not implemented"
  end

  @doc """
  Sets the stream handler associated to a protocol id.
  """
  @spec host_set_stream_handler(host, charlist) :: :ok | error
  def host_set_stream_handler(_host, _protocol_id) do
    raise "NIF host_set_stream_handler not implemented"
  end

  @doc """
  Returns an `Option` that can be passed to `host_new`
  as an argument to configures libp2p to listen on the
  given (unparsed) addresses.
  Note that the address must be a charlist.
  TODO: make it work with binaries.
  """
  @spec listen_addr_strings(charlist) :: {:ok, option} | error
  def listen_addr_strings(_addr) do
    raise "NIF listen_addr_strings not implemented"
  end

  @doc """
  Creates a new `Stream` connected to the
  peer with the given id, using the protocol with given id.
  """
  @spec host_new_stream(host, peer_id, charlist) :: {:ok, stream} | error
  def host_new_stream(_host, _peer_id, _protocol_id) do
    raise "NIF host_new_stream not implemented"
  end

  @doc """
  Gets the `Peerstore` of the given `Host`.
  """
  @spec host_peerstore(host) :: {:ok, peerstore} | error
  def host_peerstore(_host) do
    raise "NIF host_peerstore not implemented"
  end

  @doc """
  Gets the `ID` of the given `Host`.
  """
  @spec host_id(host) :: {:ok, peer_id} | error
  def host_id(_host) do
    raise "NIF host_id not implemented"
  end

  @doc """
  Gets the addresses of the given `Host`.
  """
  @spec host_addrs(host) :: {:ok, addrs} | error
  def host_addrs(_host) do
    raise "NIF host_addrs not implemented"
  end

  @doc """
  Adds the addresses of the peer with the given ID to
  the `Peerstore`. The addresses are valid for the given
  TTL.
  """
  @spec peerstore_add_addrs(peerstore, peer_id, addrs, integer) :: nil
  def peerstore_add_addrs(_peerstore, _peer_id, _addrs, _ttl) do
    raise "NIF peerstore_add_addrs not implemented"
  end

  @doc """
  Reads bytes from the stream (up to a predefined maximum).
  Note that the data is returned as a charlist.
  TODO: return a binary.
  """
  @spec stream_read(stream) :: {:ok, charlist} | error
  def stream_read(_stream) do
    raise "NIF stream_read not implemented"
  end

  @doc """
  Writes data into the stream. Note that the data must be
  a charlist.
  TODO: make it work with binaries.
  """
  @spec stream_write(stream, charlist) :: :ok | error
  def stream_write(_stream, _data) do
    raise "NIF stream_write not implemented"
  end

  @doc """
  Closes the stream.
  """
  @spec stream_close(stream) :: nil
  def stream_close(_stream) do
    raise "NIF stream_close not implemented"
  end
end
