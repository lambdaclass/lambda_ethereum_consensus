defmodule Libp2p do
  @moduledoc """
  Documentation for `Libp2p`.
  """

  @on_load :load_nifs

  def load_nifs do
    :erlang.load_nif(~c"./libp2p", 0)
  end

  @doc """
  Hello world.

  ## Examples

      iex> Libp2p.hello()
      :world

  """
  def hello do
    raise "NIF hello not implemented"
  end

  @doc """
  Test function.

  ## Examples

      iex> Libp2p.my_function(2, 3)
      8

  """
  def my_function(_a, _b) do
    raise "NIF my_function not implemented"
  end

  @doc """
  Test function that sends a message asynchronously.
  """
  def test_send_message() do
    raise "NIF test_send_message not implemented"
  end

  @doc """
  Creates a new Host.
  """
  def host_new() do
    raise "NIF host_new not implemented"
  end

  @doc """
  Deletes a Host.
  """
  def host_close(_host) do
    raise "NIF host_close not implemented"
  end

  @doc """
  Sets the stream handler associated to a protocol id.
  """
  def host_set_stream_handler(_host, _protocol_id) do
    raise "NIF host_set_stream_handler not implemented"
  end

  @doc """
  `listen_addr_strings` configures libp2p to listen on the
  given (unparsed) addresses.
  Returns an `Option` that can be passed to `host_new`
  as an argument.
  """
  def listen_addr_strings(_addr) do
    raise "NIF listen_addr_strings not implemented"
  end

  @doc """
  host_new_stream creates a new `Stream` connected to the
  peer with the given id, using the protocol with given id.
  """
  def host_new_stream(_host, _peer_id, _protocol_id) do
    raise "NIF host_new_stream not implemented"
  end

  @doc """
  host_peerstore gets the `Peerstore` of the given `Host`.
  """
  def host_peerstore(_host) do
    raise "NIF host_peerstore not implemented"
  end

  @doc """
  host_id gets the `ID` of the given `Host`.
  """
  def host_id(_host) do
    raise "NIF host_id not implemented"
  end

  @doc """
  host_id gets the addresses of the given `Host`.
  """
  def host_addrs(_host) do
    raise "NIF host_addrs not implemented"
  end
end
