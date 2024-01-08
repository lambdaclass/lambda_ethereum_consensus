defmodule BeaconApi.Utils do
  @moduledoc """
   Set of useful utilitary functions in the context of the Beacon API
  """

  @doc """
  Checks if the value is 32 bytes and starting with "0x"
  """
  @spec is_bytes32?(binary) :: boolean
  def is_bytes32?(value) when is_binary(value) do
    String.starts_with?(value, "0x") and byte_size(value) == 66
  end

  @spec parse_id(binary) :: atom | binary
  def parse_id("genesis"), do: :genesis
  def parse_id("justified"), do: :justified
  def parse_id("finalized"), do: :finalized
  def parse_id("head"), do: :head

  def parse_id("0x" <> hex_root) do
    if byte_size(hex_root) == 66 do
      <<hex_root::binary>>
    else
      :invalid_id
    end
  end

  def parse_id(slot) do
    case Integer.parse(slot) do
      {num, ""} -> num
      _ -> :invalid_id
    end
  end
end
