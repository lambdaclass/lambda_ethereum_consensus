defmodule LambdaEthereumConsensus.Utils.MerkleTrie do
  @moduledoc """
  Simple Merkle Trie implementation in Elixir using SHA-256.
  """

  defstruct [:hash, :left, :right]

  # Function to create a leaf node
  defp leaf(value) do
    hash = :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
    %{hash: hash}
  end

  # Function to create an internal node
  defp internal(left, right) do
    combined_hash = :crypto.hash(:sha256, left.hash <> right.hash) |> Base.encode16(case: :lower)
    %{hash: combined_hash, left: left, right: right}
  end

  # Function to build the Merkle Trie recursively
  defp build_merkle_tree([]), do: %{}
  defp build_merkle_tree([value]), do: leaf(value)

  defp build_merkle_tree(values) do
    {left_values, right_values} = Enum.split(values, div(length(values), 2))
    left = build_merkle_tree(left_values)
    right = build_merkle_tree(right_values)
    internal(left, right)
  end

  # Public function to create a Merkle Trie from a list of values
  def create(values) do
    build_merkle_tree(values)
  end
end
