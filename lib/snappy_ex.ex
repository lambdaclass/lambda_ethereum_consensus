defmodule LambdaEthereumConsensus.SnappyEx do
  @moduledoc """
    SSZ library in Elixir
  """

  def decompress_frames(chunks) do
    with {:ok, chunks} <- validate_stream(chunks) do
      decompress_frames(chunks, <<>>)
    end
  end

  defp decompress_frames(chunks, acc) do
    if byte_size(chunks) != 0 do
      {chunk_id, chunks} = process_chunk_id(chunks)
      {chunks_size, chunks} = process_chunk_size(chunks)
      {acc, chunks} = process_chunks(chunks, acc, chunks_size, chunk_id)
      decompress_frames(chunks, acc)
    else
      acc
    end
  end

  defp process_chunk_id(<<chunk_id::size(8), chunks::binary>>), do: {chunk_id, chunks}

  defp process_chunk_size(<<chunk_size::little-integer-size(24), chunks::binary>>),
    do: {chunk_size, chunks}

  defp validate_stream(chunks) do
    <<stream_identifier::binary-size(10), remaining_chunks::binary>> = chunks

    if stream_identifier == <<0xFF, 0x06, 0x00, 0x00, 0x73, 0x4E, 0x61, 0x50, 0x70, 0x59>> do
      {:ok, remaining_chunks}
    else
      {:error, "stream identifier not valid"}
    end
  end

  defp process_chunks(chunks, acc, size, 0xFF) do
    # process stream identifier
    # according to the specs, you just ignore it given the size and contents are correct
    <<stream_data::binary-size(size), remaining_chunks::binary>> = chunks
    {acc, remaining_chunks}
  end

  defp process_chunks(chunks, acc, size, 0x00) do
    # process compressed data
    <<checksum::binary-size(4), compressed_data::binary-size(size - 4), remaining_chunks::binary>> =
      chunks

    {:ok, decompressed_data} = :snappyer.decompress(compressed_data)
    acc = <<acc::binary, decompressed_data::binary>>
    {acc, remaining_chunks}
  end

  defp process_chunks(chunks, acc, size, 0x01) do
    # process uncompressed data
    <<checksum::binary-size(4), uncompressed_data::binary-size(size - 4),
      remaining_chunks::binary>> = chunks

    acc = <<acc::binary, uncompressed_data::binary>>
    {acc, remaining_chunks}
  end
end
