defmodule Helper do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """

  @spec uint_to_bytes(non_neg_integer) :: binary
  def uint_to_bytes(uint) do
    uint
    |> :binary.encode_unsigned(:little)
  end
end
