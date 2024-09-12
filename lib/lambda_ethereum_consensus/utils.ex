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

  @doc """
  Format a binary to a shortened hexadecimal representation.
  """
  @spec format_shorten_binary(binary) :: String.t()
  def format_shorten_binary(binary) do
    encoded = binary |> Base.encode16(case: :lower)
    "0x#{String.slice(encoded, 0, 3)}..#{String.slice(encoded, -4, 4)}"
  end

  @doc """
  Format a bitstring to a base 2 representation.
  """
  @spec format_bitstring(bitstring) :: String.t()
  def format_bitstring(bitstring) do
    # This coudl also be done with Bitwise.to_integer/1 and Integer.to_string/2 but
    # it would lack the padding.
    bitstring
    |> :binary.bin_to_list()
    |> Enum.map_join(" ", fn int -> Integer.to_string(int, 2) |> String.pad_leading(8, "0") end)
  end

  def chunk_by_sizes(enum, sizes), do: chunk_by_sizes(enum, sizes, [], 0, [])

  # No more elements, there may be a leftover chunk to add.
  def chunk_by_sizes([], _sizes, chunk, chunk_size, all_chunks) do
    if chunk_size > 0 do
      [Enum.reverse(chunk) | all_chunks] |> Enum.reverse()
    else
      Enum.reverse(all_chunks)
    end
  end

  # No more splits will be done. We just performed a split.
  def chunk_by_sizes(enum, [], [], 0, all_chunks), do: [enum | Enum.reverse(all_chunks)]

  def chunk_by_sizes(enum, [size | rem_sizes] = sizes, chunk, chunk_size, all_chunks) do
    if chunk_size == size do
      chunk_by_sizes(enum, rem_sizes, [], 0, [Enum.reverse(chunk) | all_chunks])
    else
      [elem | rem_enum] = enum
      chunk_by_sizes(rem_enum, sizes, [elem | chunk], chunk_size + 1, all_chunks)
    end
  end
end
