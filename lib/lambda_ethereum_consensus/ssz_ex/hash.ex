defmodule LambdaEthereumConsensus.SszEx.Hash do
  @moduledoc """
  Hash
  """

  @bytes_per_chunk 32
  @max_merkle_tree_depth 64

  @doc """
  Compute the roots of Merkle trees with all zero leaves and lengths from 0 to 64.
  """
  def compute_zero_hashes do
    Stream.iterate(<<0::size(8 * @bytes_per_chunk)>>, &hash_nodes(&1, &1))
    |> Stream.take(@max_merkle_tree_depth + 1)
    |> Enum.join()
  end

  @doc """
  Given the output of `compute_zero_hashes` as second argument, return the root of
  an all-zero Merkle tree of the given depth.
  """
  def get_zero_hash(depth, zero_hashes) when depth in 0..@max_merkle_tree_depth do
    offset = (depth + 1) * @bytes_per_chunk - @bytes_per_chunk
    <<_::binary-size(offset), hash::binary-size(@bytes_per_chunk), _::binary>> = zero_hashes
    hash
  end

  @compile {:inline, hash: 1}
  @spec hash(iodata()) :: binary()
  def hash(data), do: :crypto.hash(:sha256, data)

  @spec hash_nodes(binary(), binary()) :: binary()
  def hash_nodes(left, right), do: :crypto.hash(:sha256, left <> right)
end
