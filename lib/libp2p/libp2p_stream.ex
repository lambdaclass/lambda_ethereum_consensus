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
      fn -> {stream, :ok} end,
      &stream_next/1,
      fn {st, _} -> Libp2p.stream_close(st) end
    )
  end

  defp stream_next({stream, :error}), do: {:halt, {stream, :error}}

  defp stream_next({stream, :ok}) do
    case Libp2p.stream_read(stream) do
      {:ok, ""} -> {:halt, {stream, :ok}}
      {res, chunk} -> {[{res, chunk}], {stream, res}}
    end
  end
end
