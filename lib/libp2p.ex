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
  Hello world.

  ## Examples

      iex> Libp2p.my_function(2, 3)
      8

  """
  def my_function(_a, _b) do
    raise "NIF my_function not implemented"
  end

  @doc """
  Hello world.

  ## Examples

      iex> Libp2p.host_new()
      :ok

  """
  def host_new() do
    raise "NIF host_new not implemented"
  end
end
