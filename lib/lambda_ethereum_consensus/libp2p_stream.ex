defmodule Libp2p.Stream do
  @moduledoc """
  Wrapper over a stream handle.
  TODO: make this a RW stream
  """

  @doc """
  Creates a new `Stream` connected to the
  peer with the given id, using the protocol with given id.
  It returns an `Enumerable` that can be used to read.
  """
  @spec from(Libp2p.stream()) :: Enumerable.t()
  def from(stream) do
    Stream.resource(
      fn -> {stream, ""} end,
      &stream_next/1,
      fn {st, _} -> Libp2p.stream_close(st) end
    )
  end

  defp stream_next({stream, ""}) do
    case Libp2p.stream_read(stream) do
      {:ok, <<x, chunk::binary>>} -> {[<<x>>], {stream, chunk}}
      {:ok, ""} -> {:halt, {stream, ""}}
      {:error, message} -> raise(message)
    end
  end

  defp stream_next({stream, <<x, rest::binary>>}) do
    {[<<x>>], {stream, rest}}
  end
end
