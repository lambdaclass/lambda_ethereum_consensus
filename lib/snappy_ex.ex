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
  @id_stream_identifier 0xFF

  def decompress(<<@id_stream_identifier>> <> _ = chunks), do: decompress_frames(chunks, <<>>)
  def decompress(_chunks), do: {:error, "no stream identifier at beginning"}

  defp decompress_frames("", acc), do: {:ok, acc}

  defp decompress_frames(chunks, acc) do
    with {:ok, {id, data, remaining_chunks}} <- process_chunk_metadata(chunks),
         {:ok, new_acc} <- apply_chunks(acc, id, data) do
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

  # process stream identifier
  # according to the specs, you just ignore it given the size and contents are correct
  defp apply_chunks(acc, @id_stream_identifier, @stream_identifier), do: {:ok, acc}
  defp apply_chunks(_, @id_stream_identifier, _), do: {:error, "invalid stream identifier"}

  defp apply_chunks(_acc, @id_compressed_data, data)
       when byte_size(data) > @chunk_size_limit,
       do: {:error, "chunk is bigger than limit"}

  defp apply_chunks(acc, @id_compressed_data, data) do
    # process compressed data
    <<masked_checksum::little-size(32), compressed_data::binary>> = data

    with {:ok, decompressed_data} <- :snappyer.decompress(compressed_data) do
      masked_computed_checksum = compute_masked_checksum(decompressed_data)

      if masked_computed_checksum == masked_checksum do
        acc = <<acc::binary, decompressed_data::binary>>
        {:ok, acc}
      else
        {:error, "compressed chunks checksum invalid"}
      end
    end
  end

  # Uncompressed chunks
  defp apply_chunks(_acc, @id_uncompressed_data, data)
       when byte_size(data) > @chunk_size_limit,
       do: {:error, "chunk is bigger than limit"}

  defp apply_chunks(acc, @id_uncompressed_data, data) do
    # process uncompressed data
    <<masked_checksum::little-size(32), uncompressed_data::binary>> = data

    masked_computed_checksum = compute_masked_checksum(uncompressed_data)

    if masked_computed_checksum == masked_checksum do
      acc = <<acc::binary, uncompressed_data::binary>>
      {:ok, acc}
    else
      {:error, "uncompressed chunks checksum invalid"}
    end
  end

  defp compute_masked_checksum(data) when is_binary(data) do
    checksum = Crc32c.calc!(data)

    # the crc32c checksum of the uncompressed data is masked before inserted into the
    # frame using masked_checksum = ((checksum >> 15) | (checksum << 17)) + 0xa282ead8
    (checksum >>> 15 ||| checksum <<< 17) + 0xA282EAD8 &&& @bit_mask_32
  end
end
