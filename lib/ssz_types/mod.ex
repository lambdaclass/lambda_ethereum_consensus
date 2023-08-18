defmodule SszTypes do
  @moduledoc """
  Lists some types used in SSZ structs.
  """
  # Integer types
  @type u64 :: 0..unquote(2 ** 64 - 1)

  # Binary types
  @type h32 :: <<_::32>>
  @type h256 :: <<_::256>>
end
