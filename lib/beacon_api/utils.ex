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
end
