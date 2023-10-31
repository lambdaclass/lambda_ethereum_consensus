defmodule LambdaEthereumConsensus.Utils.Diff do
  @moduledoc """
  A module to compare between different structures and get their differences. Useful for debugging.
  """
  def diff(a, b) when is_map(a) and is_map(b) do
    d = %{}

    d
    |> maybe_added(a, b)
    |> unchanged_if_empty()
  end

  def diff(a, b) when is_list(a) and is_list(b) do
    d = %{}

    d
    |> maybe_added(a, b, :added_left)
    |> maybe_added(b, a, :added_right)
    |> changes(a, b)
    |> unchanged_if_empty()
  end

  def diff(a, a), do: :unchanged
  def diff(a, b), do: %{left: a, right: b}

  defp maybe_added(d, a, b) when is_map(a) and is_map(b) do
    a_keys = a |> Map.keys() |> MapSet.new()
    b_keys = b |> Map.keys() |> MapSet.new()

    a_extra =
      MapSet.difference(a_keys, b_keys) |> Enum.map(fn k -> {k, a[k]} end)

    b_extra =
      MapSet.difference(b_keys, a_keys) |> Enum.map(fn k -> {k, b[k]} end)

    d
    |> add_if_not_empty(:added_left, a_extra)
    |> add_if_not_empty(:added_right, b_extra)
  end

  defp maybe_added(d, a, b, key) when is_list(a) and is_list(b) do
    Enum.slice(a, length(b), length(a))
    |> then(&add_if_not_empty(d, key, &1))
  end

  defp changes(d, a, b) when is_list(a) and is_list(b) do
    Enum.zip(a, b)
    |> Enum.with_index()
    |> Enum.map(&compare/1)
    |> Enum.reject(&(&1 == :unchanged))
    |> then(&add_if_not_empty(d, :changed, &1))
  end

  defp add_if_not_empty(map, _key, []), do: map
  defp add_if_not_empty(map, key, element), do: Map.put(map, key, element)

  defp compare({{a, a}, _}), do: :unchanged
  defp compare({{a, b}, idx}), do: {idx, diff(a, b)}
  defp unchanged_if_empty(d), do: if(d == %{}, do: :unchanged, else: d)
end
