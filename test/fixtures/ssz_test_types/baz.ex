defmodule Fixtures.SszTestTypes.Baz do
  @moduledoc false
  fields = [
    :static_a,
    :static_b
  ]

  @schema [
    %{static_a: %{type: :uint, size: 64}},
    %{static_b: %{type: :uint, size: 64}}
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          static_a: SszTypes.uint64(),
          static_b: SszTypes.uint64()
        }
  def schema, do: @schema
end
