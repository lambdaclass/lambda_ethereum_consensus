defmodule Snappy do
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "snappy"

  def decompress(stream) do
    case decompressor_new() do
      {:ok, decompressor} ->
        {:ok,
         Stream.transform(
           stream,
           fn -> decompressor end,
           &reducer/2,
           &last_fun/1,
           fn _ -> nil end
         )}

      err ->
        err
    end
  end

  def decompress!(stream) do
    case decompress(stream) do
      {:ok, res} ->
        res

      {:error, err} ->
        raise(err)
    end
  end

  defp reducer(chunk, decompressor) when is_binary(chunk) do
    decompressor_feed(decompressor, chunk)

    result =
      case decompressor_read(decompressor) do
        {:ok, :paused} ->
          []

        {:ok, ""} ->
          :halt

        {:ok, chunk} ->
          binary_to_stream(chunk)

        {:error, err} ->
          raise(err)
      end

    {result, decompressor}
  end

  defp reducer(chunk, decompressor) do
    reducer(to_string(chunk), decompressor)
  end

  defp last_fun(decompressor) do
    result = reducer("", decompressor)
    result
  end

  defp binary_to_stream(bin) do
    Stream.unfold(bin, fn
      "" -> nil
      <<x, rest::binary>> -> {x, rest}
    end)
  end

  def decompressor_new(), do: :erlang.nif_error(:nif_not_loaded)

  def decompressor_feed(_decompressor, _bytes),
    do: :erlang.nif_error(:nif_not_loaded)

  def decompressor_read(_decompressor), do: :erlang.nif_error(:nif_not_loaded)
end
