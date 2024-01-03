defmodule LambdaEthereumConsensus.SnappyEx do
  @moduledoc """
    SSZ library in Elixir
  """

  def decompress_frames(chunks) do
    with {:ok, chunks} <- validate_stream(chunks) do
      decompress_frames(chunks, <<>>)
    end
  end

  defp decompress_frames(chunks, acc) when byte_size(chunks) == 0, do: acc

  defp decompress_frames(chunks, acc) do
    with {:ok, {chunk_id, chunk_size, chunks}} <- process_chunk_metadata(chunks),
         {:ok, {acc, chunks}} <- process_chunks(chunks, acc, chunk_size, chunk_id) do
      decompress_frames(chunks, acc)
    end
  end

  # chunk layout: 1-byte chunk_id, 3-bytes chunk_size, remaining chunks if any data present.
  defp process_chunk_metadata(chunks) when byte_size(chunks) < 4,
    do: {:error, "invalid chunks metadata size"}

  defp process_chunk_metadata(chunks) do
    {:ok, {<<chunk_id::size(8), chunks_size::size(24), chunks::binary>>}}
  end

  defp validate_stream(chunks) do
    <<stream_identifier::binary-size(10), remaining_chunks::binary>> = chunks

    if stream_identifier == <<0xFF, 0x06, 0x00, 0x00, 0x73, 0x4E, 0x61, 0x50, 0x70, 0x59>> do
      {:ok, remaining_chunks}
    else
      {:error, "invalid stream identifier"}
    end
  end

  defp process_chunks(chunks, acc, size, 0xFF) when byte_size(chunks) < size,
    do: {:error, "invalid size: stream identifier chunks"}

  defp process_chunks(chunks, acc, size, 0xFF) do
    # process stream identifier
    # according to the specs, you just ignore it given the size and contents are correct
    <<stream_data::binary-size(size), remaining_chunks::binary>> = chunks
    {:ok, {acc, remaining_chunks}}
  end

  defp process_chunks(chunks, acc, size, 0x00)
       when byte_size(chunks) < size || byte_size(chunks) > 65540,
       do: {:error, "invalid size: compressed data chunks"}

  defp process_chunks(chunks, acc, size, 0x00) do
    # process compressed data
    <<checksum::binary-size(4), compressed_data::binary-size(size - 4), remaining_chunks::binary>> =
      chunks

    with {:ok, decompressed_data} <- :snappyer.decompress(compressed_data),
         {:ok, computed_checksum} <- :erlang.crc32(decompressed_data) do
      if computed_checksum == checksum do
        acc = <<acc::binary, decompressed_data::binary>>
        {:ok, {acc, remaining_chunks}}
      else
        {:error, "compressed chunks checksum invalid"}
      end
    end
  end

  defp process_chunks(chunks, acc, size, 0x01) do
    # process uncompressed data
    <<checksum::binary-size(4), uncompressed_data::binary-size(size - 4),
      remaining_chunks::binary>> = chunks

    with {:ok, computed_checksum} <- :erlang.crc32(uncompressed_data) do
      if computed_checksum == checksum do
        acc = <<acc::binary, uncompressed_data::binary>>
        {:ok, {acc, remaining_chunks}}
      else
        {:error, "uncompressed chunks checksum invalid"}
      end
    end
  end
end
