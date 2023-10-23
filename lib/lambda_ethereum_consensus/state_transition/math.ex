defmodule LambdaEthereumConsensus.StateTransition.Math do
  @moduledoc """
  Math functions
  """

  @spec uint_to_bytes(SszTypes.uint64()) :: binary
  def uint_to_bytes(value) when is_integer(value) do
    byte_size = calculate_byte_size(value)
    big_endian_bytes = <<value::size(byte_size*8)>>
    big_endian_bytes
    |> :binary.bin_to_list()
    |> Enum.reverse()
    |> :binary.list_to_bin()
  end

  defp calculate_byte_size(0), do: 1
  defp calculate_byte_size(n) when n > 0 do
    calculate_byte_size(n, 0)
  end

  defp calculate_byte_size(0, size), do: size
  defp calculate_byte_size(n, size) do
    calculate_byte_size(div(n, 256), size + 1)
  end

  @doc """
  Return the largest integer ``x`` such that ``x**2 <= n``.
  """
  @spec integer_squareroot(SszTypes.uint64()) :: SszTypes.uint64()
  def integer_squareroot(n) when is_integer(n) do
    compute_root(n, n, div(n + 1, 2))
  end

  defp compute_root(n, x, y) when y < x do
    compute_root(n, y, div(y + div(n, y), 2))
  end

  defp compute_root(_n, x, _y), do: x
end
