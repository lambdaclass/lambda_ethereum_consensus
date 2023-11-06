defmodule LambdaEthereumConsensus.StateTransition.Math do
  @moduledoc """
  Math functions
  """

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
