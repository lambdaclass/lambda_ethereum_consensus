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
  def parse_yaml({"extra_data", x}), do: {:extra_data, parse_as_string(x)}
  def parse_yaml({"transactions", list}), do: {:transactions, Enum.map(list, &parse_as_string/1)}
  def parse_yaml({k, v}), do: {String.to_atom(k), parse_yaml(v)}
  def parse_yaml("0x" <> hash), do: Base.decode16!(hash, [{:case, :lower}])
  def parse_yaml("0x"), do: ""

  def parse_yaml(x) when is_binary(x) do
    {num, ""} = Integer.parse(x)
    num
  end

  def parse_yaml(v), do: v

  # Some values are wrongly formatted as integers sometimes
  defp parse_as_string(x) when is_integer(x), do: :binary.encode_unsigned(x, :little)
  defp parse_as_string("0x" <> hash), do: Base.decode16!(hash, [{:case, :lower}])
end
