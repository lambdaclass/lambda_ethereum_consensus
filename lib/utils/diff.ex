defmodule LambdaEthereumConsensus.Utils.Diff do
  @moduledoc """
  A module to compare between different structures and get their differences. Useful for debugging.
  """

  def diff(a, b) when is_list(a) and is_list(b) do
    d = %{}

    d
    |> maybe_added(a, b, :added_left)
    |> maybe_added(b, a, :added_right)
    |> changes(a, b)
    |> then(fn d -> if d == %{}, do: :unchanged, else: d end)
  end

  def diff(a, a), do: :unchanged
  def diff(a, b), do: %{left: a, right: b}

  defp maybe_added(d, a, b, key) do
    extra = Enum.slice(a, length(b), length(a))
    if extra == [], do: d, else: Map.put(d, key, extra)
  end

  defp changes(d, a, b) when is_list(a) and is_list(b) do
    changes =
      Enum.zip(a, b)
      |> Enum.with_index()
      |> Enum.map(&compare/1)
      |> Enum.reject(&(&1 == :unchanged))

    if changes == [], do: d, else: Map.put(d, :changed, changes)
  end

  defp compare({{a, a}, _}), do: :unchanged
  defp compare({{a, b}, idx}), do: {idx, diff(a, b)}
end
