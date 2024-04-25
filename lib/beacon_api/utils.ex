defmodule BeaconApi.Utils do
  @moduledoc """
   Set of useful utilitary functions in the context of the Beacon API
  """
  alias BeaconApi.Helpers
  alias LambdaEthereumConsensus.Utils.BitList

  @spec parse_id(binary) :: Helpers.block_id()
  def parse_id("genesis"), do: :genesis
  def parse_id("justified"), do: :justified
  def parse_id("finalized"), do: :finalized
  def parse_id("head"), do: :head

  def parse_id("0x" <> hex_root) when byte_size(hex_root) == 64 do
    case Base.decode16(hex_root) do
      {:ok, decoded} -> decoded
      :error -> :invalid_id
    end
  end

  def parse_id("0x" <> _hex_root), do: :invalid_id

  def parse_id(slot) do
    case Integer.parse(slot) do
      {num, ""} -> num
      _ -> :invalid_id
    end
  end

  def hex_encode(binary) when is_binary(binary) do
    "0x" <> Base.encode16(binary, case: :lower)
  end

  defp to_json(attribute, module) when is_struct(attribute) do
    module.schema()
    |> Enum.map(fn {k, schema} ->
      {k, Map.fetch!(attribute, k) |> to_json(schema)}
    end)
    |> Map.new()
  end

  defp to_json(binary, {:byte_list, _}), do: to_json(binary)
  defp to_json(binary, {:byte_vector, _}), do: to_json(binary)

  defp to_json(list, {x, schema, _}) when x in [:list, :vector],
    do: Enum.map(list, fn elem -> to_json(elem, schema) end)

  defp to_json(bitlist, {:bitlist, _}) do
    bitlist
    |> BitList.to_bytes()
    |> hex_encode()
  end

  defp to_json(v, _schema), do: to_json(v)

  def to_json(%name{} = v), do: to_json(v, name)
  def to_json({k, v}), do: {k, to_json(v)}
  def to_json(x) when is_binary(x), do: hex_encode(x)
  def to_json(v), do: inspect(v)
end
