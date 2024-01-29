defmodule LambdaEthereumConsensus.Utils.ZeroHashes do
  @moduledoc """
  Precomputed zero hashes
  """

  @bits_per_byte 8
  @bytes_per_chunk 32
  @bits_per_chunk @bytes_per_chunk * @bits_per_byte
  @max_merkle_tree_depth 64

  def compute_zero_hashes do
    buffer = <<0::size(@bytes_per_chunk * @max_merkle_tree_depth * @bits_per_byte)>>

    0..(@max_merkle_tree_depth - 2)
    |> Enum.reduce(buffer, fn index, acc_buffer ->
      start = index * @bytes_per_chunk
      stop = (index + 2) * @bytes_per_chunk
      focus = acc_buffer |> :binary.part(start, stop - start)
      <<left::binary-size(@bytes_per_chunk), _::binary>> = focus
      hash = hash_nodes(left, left)
      change_index = (index + 1) * @bytes_per_chunk
      replace_chunk(acc_buffer, change_index, hash)
    end)
  end

  defp hash_nodes(left, right), do: :crypto.hash(:sha256, left <> right)

  defp replace_chunk(chunks, start, new_chunk) do
    <<left::binary-size(start), _::size(@bits_per_chunk), right::binary>> =
      chunks

    <<left::binary, new_chunk::binary, right::binary>>
  end
end
