defmodule SpecTestUtils do
  @moduledoc """
  Utilities for spec tests.
  """

  def parse_yaml(map) when is_map(map) do
    map
    |> Stream.map(&parse_yaml/1)
    |> Map.new()
  end

  def parse_yaml(list) when is_list(list), do: Enum.map(list, &parse_yaml/1)
  def parse_yaml({k, v}), do: {String.to_atom(k), parse_yaml(v)}
  def parse_yaml("0x" <> hash), do: Base.decode16!(hash, [{:case, :lower}])
  def parse_yaml(v), do: v
end
