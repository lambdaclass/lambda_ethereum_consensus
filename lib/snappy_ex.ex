defmodule SnappyEx do
  import Bitwise
  import Crc32c

  @moduledoc """
    SSZ library in Elixir
  """
  @bit_mask_32 2 ** 32 - 1
  @chunk_size_limit 65_540

  def decompress_frames(chunks) do
    with {:ok, chunks} <- validate_stream_id(chunks) do
      decompress_frames(chunks, <<>>)
    end
  end

  defp decompress_frames(chunks, acc) when byte_size(chunks) == 0, do: {:ok, acc}

  defp decompress_frames(chunks, acc) do
    with {:ok, {id, data, remaining_chunks}} <- process_chunk_metadata(chunks),
         {:ok, new_acc} <- apply_chunks(acc, id, data) do
      decompress_frames(remaining_chunks, new_acc)
    end
  end

  # chunk layout: 1-byte chunk_id, 3-bytes chunk_size, remaining chunks if any data present.
  defp process_chunk_metadata(chunks) when byte_size(chunks) < 4,
    do: {:error, "invalid chunks metadata size"}

  defp process_chunk_metadata(chunks) do
    <<chunk_id::size(8), chunks_size::little-size(24), chunks::binary>> = chunks

    with {:ok, {data, remaining_chunks}} <- extract_chunk_data(chunks_size, chunks) do
      {:ok, {chunk_id, data, remaining_chunks}}
    end
  end

  defp extract_chunk_data(size, chunks) when byte_size(chunks) < size,
    do: {:error, "invalid chunk size"}

  defp extract_chunk_data(size, chunks) do
    <<data::binary-size(size), remaining_chunks::binary>> = chunks
    {:ok, {data, remaining_chunks}}
  end

  # Validates that the stream identifier is present at the beginning of the stream. If successful,
  # returns the stream with the identifier removed. If not, returns an error tuple.
  defp validate_stream_id(chunks) when byte_size(chunks) < 10 do
    {:error, "stream identifier invalid size"}
  end

  defp validate_stream_id(data) do
    <<stream_identifier::binary-size(10), remaining_chunks::binary>> = data

    with {:ok, _acc} <- apply_chunks(<<>>, 0xFF, stream_identifier) do
      {:ok, remaining_chunks}
    end
  end

  defp apply_chunks(acc, 0xFF, data) do
    # process stream identifier
    # according to the specs, you just ignore it given the size and contents are correct
    if data == <<0xFF, 0x06, 0x00, 0x00, 0x73, 0x4E, 0x61, 0x50, 0x70, 0x59>> do
      {:ok, acc}
    else
      {:error, "invalid stream identifier"}
    end
  end

  defp apply_chunks(_acc, 0x00, data)
       when byte_size(data) > @chunk_size_limit,
       do: {:error, "invalid size: compressed data chunks"}

  defp apply_chunks(acc, 0x00, data) do
    # process compressed data
    <<masked_checksum::little-size(32), compressed_data::binary>> =
      data

    with {:ok, decompressed_data} <- :snappyer.decompress(compressed_data) do
      # the crc32 checksum of the uncompressed data is masked before inserted into the frame using masked_checksum = ((checksum >> 15) | (checksum << 17)) + 0xa282ead8
      masked_computed_checksum =
        masked_checksum(decompressed_data)

      IO.inspect(masked_checksum, label: "masked_checksum compressed")
      IO.inspect(masked_computed_checksum, label: "masked_computed_checksum compressed")

      if masked_computed_checksum == masked_checksum do
        acc = <<acc::binary, decompressed_data::binary>>
        {:ok, acc}
      else
        {:error, "compressed chunks checksum invalid"}
      end
    end
  end

  # Uncompressed chunks
  defp apply_chunks(_acc, 0x01, data)
       when byte_size(data) > @chunk_size_limit,
       do: {:error, "invalid size: uncompressed data chunks"}

  defp apply_chunks(acc, 0x01, data) do
    # process uncompressed data
    <<masked_checksum::little-size(32), uncompressed_data::binary>> = data

    # the crc32 checksum of the uncompressed data is masked before inserted into the frame using masked_checksum = ((checksum >> 15) | (checksum << 17)) + 0xa282ead8
    masked_computed_checksum =
      masked_checksum(uncompressed_data)

    IO.inspect(masked_checksum, label: "masked_checksum uncompressed")
    IO.inspect(masked_computed_checksum, label: "masked_computed_checksum uncompressed")

    if masked_computed_checksum == masked_checksum do
      acc = <<acc::binary, uncompressed_data::binary>>
      {:ok, acc}
    else
      {:error, "uncompressed chunks checksum invalid"}
    end
  end

  defp masked_checksum(checksum) do
    checksum = Crc32c.calc!(uncompressed_data)

    checksum_mask =
      (checksum >>> 15 |||
         (checksum <<< 17 &&& @bit_mask_32)) +
        0xA282EAD8 &&& @bit_mask_32

    checksum_mask
  end
end
