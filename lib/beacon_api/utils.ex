defmodule BeaconApi.Utils do
  @moduledoc """
   Set of useful utilitary functions in the context of the Beacon API
  """
  alias LambdaEthereumConsensus.ForkChoice.Helpers

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
end
