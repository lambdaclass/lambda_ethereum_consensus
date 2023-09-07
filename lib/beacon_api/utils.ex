defmodule BeaconApi.Utils do
  def is_bytes32?(value) when is_binary(value) do
    String.starts_with?(value, "0x") and byte_size(value) == 66
  end
end
