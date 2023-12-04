defmodule LambdaEthereumConsensus.Utils do
  @moduledoc """
  Set of utility functions used throughout the project.
  """

  @doc """
  If ``condition`` is true, run ``fun`` on ``value`` and return the result.
  Else return the unmodified ``value``.
  Accepts a predicate (arity 1) function as a ``condition``.

  ## Examples
      iex> Utils.if_then_update(1, false, &(&1 + 1))
      1
      iex> Utils.if_then_update(1, true, &(&1 + 1))
      2
      iex> Utils.if_then_update(1, &(&1 > 3), &(&1 + 1))
      1
      iex> Utils.if_then_update(1, &(&1 > 0), &(&1 + 1))
      2
  """
  @spec if_then_update(any(), boolean() | (any() -> boolean()), (any() -> any())) :: any()
  def if_then_update(value, true, fun), do: fun.(value)
  def if_then_update(value, false, _fun), do: value
  def if_then_update(value, pred, fun), do: if_then_update(value, pred.(value), fun)

  @doc """
  If first arg is an ``{:ok, value}`` tuple, apply ``fun`` to ``value`` and
  return the result. Else, if it's an ``{:error, _}`` tuple, returns it.
  """
  @spec map_ok({:ok | :error, any()}, (any() -> any())) :: any() | {:error, any()}
  def map_ok({:ok, value}, fun), do: fun.(value)
  def map_ok({:error, _} = err, _fun), do: err

  @doc """
  If first arg is an ``{:error, reason}`` tuple, replace ``reason`` with
  ``new_reason``. Else, return the first arg unmodified.
  """
  @spec map_err(any() | {:error, String.t()}, String.t()) :: any() | {:error, String.t()}
  def map_err({:error, _}, reason), do: {:error, reason}
  def map_err(v, _), do: v
end
