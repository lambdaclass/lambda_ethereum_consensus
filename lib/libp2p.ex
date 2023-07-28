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
end
