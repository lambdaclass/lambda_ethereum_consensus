defmodule LambdaEthereumConsensus.SnappyEx do
  @moduledoc """
    SSZ library in Elixir
  """

  def decompress_frames(chunks, acc \\ <<>>) do
    if byte_size(chunks) != 0 do
      {chunk_id, chunks} = process_chunk_id(chunks)
      {chunks_size, chunks} = process_chunk_size(chunks)
      {acc, chunks} = process_chunks(chunks, chunks_size, chunk_id, acc)
      decompress_frames(chunks, acc)
    else
      acc
    end
  end

  def process_chunk_id(<<chunk_id::size(8), chunks::binary>>), do: {chunk_id, chunks}

  def process_chunk_size(<<b2::size(8), b1::size(8), b0::size(8), chunks::binary>>) do
    chunk_size = b2 + b1 + b0
    {chunk_size, chunks}
  end

  def process_chunks(chunks, size, chunk_id, acc) do
    {local_acc, chunks} =
      case chunk_id do
        0xFF -> process_stream_chunks(chunks, size)
      end

    acc = <<acc::binary, local_acc::binary>>
    {acc, chunks}
  end

  def process_stream_chunks(chunks, size) do
    <<stream_data::binary-size(size), remaining_chunks::binary>> = chunks
    {stream_data, remaining_chunks}
  end
end
