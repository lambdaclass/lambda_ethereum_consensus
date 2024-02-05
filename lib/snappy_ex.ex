defmodule SnappyEx do
  @moduledoc """
    SSZ library in Elixir
  """
  import Bitwise

  @bit_mask_32 2 ** 32 - 1
  @chunk_size_limit 65_540

  @stream_identifier "sNaPpY"

  @id_compressed_data 0x00
  @id_uncompressed_data 0x01
  @id_padding 0xFE
  @id_stream_identifier 0xFF

  @ids_payload_chunks [@id_compressed_data, @id_uncompressed_data]
  @ids_reserved_unskippable_chunks 0x02..0x7F
  @ids_reserved_skippable_chunks 0x80..0xFD

  @spec decompress(nonempty_binary()) :: {:ok, binary()} | {:error, String.t()}
  def decompress(<<@id_stream_identifier>> <> _ = chunks), do: decompress_frames(chunks, <<>>)

  @spec decompress(<<>>) :: {:error, String.t()}
  def decompress(chunks) when is_binary(chunks), do: {:error, "no stream identifier at beginning"}

  defp decompress_frames("", acc), do: {:ok, acc}

  defp decompress_frames(chunks, acc) do
    with {:ok, {id, data, remaining_chunks}} <- process_chunk_metadata(chunks),
         {:ok, new_acc} <- parse_chunk(acc, id, data) do
      decompress_frames(remaining_chunks, new_acc)
    end
  end

  # chunk layout: 1-byte chunk_id, 3-bytes chunk_size, remaining chunks if any data present.
  defp process_chunk_metadata(chunks) when byte_size(chunks) < 4,
    do: {:error, "header too small"}

  defp process_chunk_metadata(<<_id::size(8), size::little-size(24), rest::binary>>)
       when byte_size(rest) < size,
       do: {:error, "missing data in chunk. expected: #{byte_size(rest)}. got: #{size}"}

  defp process_chunk_metadata(<<id::size(8), size::little-size(24), rest::binary>>) do
    <<chunk::binary-size(size), remaining_chunks::binary>> = rest
    {:ok, {id, chunk, remaining_chunks}}
  end

  # Stream identifier
  # NOTE: it can appear more than once, and must be validated each time
  defp parse_chunk(acc, @id_stream_identifier, @stream_identifier), do: {:ok, acc}
  defp parse_chunk(_, @id_stream_identifier, _), do: {:error, "invalid stream identifier"}

  # Data-carrying chunks (compressed or uncompressed)
  defp parse_chunk(_acc, id, data)
       when id in @ids_payload_chunks and byte_size(data) > @chunk_size_limit,
       do: {:error, "chunk is bigger than limit"}

  defp parse_chunk(acc, id, data) when id in @ids_payload_chunks do
    <<checksum::little-size(32), compressed_data::binary>> = data

    with {:ok, uncompressed_data} <- decompress_payload(id, compressed_data),
         :ok <- verify_checksum(uncompressed_data, checksum) do
      {:ok, <<acc::binary, uncompressed_data::binary>>}
    end
  end

  # Skippable chunks (padding or reserved)
  defp parse_chunk(acc, id, _data)
       when id == @id_padding or id in @ids_reserved_skippable_chunks,
       do: {:ok, acc}

  # Reserved unskippable chunks
  defp parse_chunk(_acc, id, _data) when id in @ids_reserved_unskippable_chunks,
    do: {:error, "unskippable chunk of type: #{id}"}

  defp decompress_payload(@id_compressed_data, data), do: :snappyer.decompress(data)
  defp decompress_payload(@id_uncompressed_data, data), do: {:ok, data}

  defp compute_checksum(data) when is_binary(data) do
    checksum = Crc32c.calc!(data)

    # the crc32c checksum of the uncompressed data is masked before inserted into the
    # frame using masked_checksum = ((checksum >> 15) | (checksum << 17)) + 0xa282ead8
    (checksum >>> 15 ||| checksum <<< 17) + 0xA282EAD8 &&& @bit_mask_32
  end

  defp verify_checksum(data, checksum) do
    if checksum == compute_checksum(data),
      do: :ok,
      else: {:error, "invalid checksum"}
  end
end
