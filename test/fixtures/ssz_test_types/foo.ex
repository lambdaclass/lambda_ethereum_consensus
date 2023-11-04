defmodule Fixtures.SszTestTypes.Foo do
  @moduledoc false
  fields = [
    :field_a,
    :list_a,
    :static_a
  ]

  @schema [
    %{field_a: %{type: :bytes, size: 48}},
    %{
      list_a: %{
        type: :list,
        schema: %{type: :container, schema: Fixtures.SszTestTypes.Baz},
        max_size: 112_234
      }
    },
    %{static_a: %{type: :uint, size: 64}}
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          field_a: SszTypes.bls_pubkey(),
          list_a: list(Fixtures.SszTestTypes.Baz.t()),
          static_a: SszTypes.uint64()
        }
  def schema, do: @schema
end
