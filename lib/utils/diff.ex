defmodule LambdaEthereumConsensus.Utils.Diff do
  @moduledoc """
  A module to compare between different structures and get their differences.
  Useful for debugging.

  Most typical cases are maps and lists, which recurse in their elements.
  Any other type is just compared with ==. Tuples may be added if needed,
  but it wasn't the case yet.

  Possible results:
  - When comparing any two elements that are equal, the result is :unchanged.
  - When comparing different maps or lists, the result will be a map containing the keys
    :added_right, :added_left and :changed.

  Diff attributes:
  - :added_right or :added_left are lists of elements. When comparing lists, this will
    just be the elements that were added. In the case of maps, they are keyword lists
    showing the key and the value that were added.
  - :changed is always a keyword list. In the case of lists, keys are indices of the
    changed elements and values are the elements themselves. In the case of maps, the keys
    are the keys of the map.
  """
  @type structured_diff :: %{
          optional(:added_left) => [any()],
          optional(:added_right) => [any()],
          optional(:changed) => Keyword.t()
        }
  @type base_diff :: %{optional(:left) => any(), optional(:right) => any()}
  @type t :: :unchanged | base_diff() | structured_diff()

  @spec diff(any(), any()) :: t()
  def diff(%Aja.Vector{} = a, %Aja.Vector{} = b) do
    diff(Enum.to_list(a), Enum.to_list(b))
  end

  def diff(a, b) when is_map(a) and is_map(b) do
    %{}
    |> maybe_added(a, b)
    |> changes(a, b)
    |> unchanged_if_empty()
  end

  def diff(a, b) when is_list(a) and is_list(b) do
    %{}
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
      MapSet.difference(a_keys, b_keys) |> Enum.map(fn k -> {k, Map.fetch!(a, k)} end)

    b_extra =
      MapSet.difference(b_keys, a_keys) |> Enum.map(fn k -> {k, Map.fetch!(b, k)} end)

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

  defp changes(d, a, b) when is_map(a) and is_map(b) do
    a_keys = a |> Map.keys() |> MapSet.new()
    b_keys = b |> Map.keys() |> MapSet.new()

    MapSet.intersection(a_keys, b_keys)
    |> Enum.map(fn k -> {k, diff(Map.get(a, k), Map.get(b, k))} end)
    |> Enum.reject(fn {_k, v} -> v == :unchanged end)
    |> then(&add_if_not_empty(d, :changed, &1))
  end

  defp add_if_not_empty(map, _key, []), do: map
  defp add_if_not_empty(map, key, element), do: Map.put(map, key, element)

  defp compare({{a, a}, _}), do: :unchanged
  defp compare({{a, b}, idx}), do: {idx, diff(a, b)}
  defp unchanged_if_empty(d), do: if(d == %{}, do: :unchanged, else: d)
end
