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
  def parse_id("0x" <> hex_root), do: <<hex_root::binary>>
  def parse_id(_other), do: :invalid_id
end
