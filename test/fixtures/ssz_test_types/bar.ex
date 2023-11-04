defmodule Fixtures.SszTestTypes.Bar do
  @moduledoc false
  fields = [
    :field_static_a,
    :container_static_b,
    :list_a,
    :field_static_c,
    :int_a,
    :vec_a
  ]

  @schema [
    %{field_static_a: %{type: :bytes, size: 32}},
    %{container_static_b: %{type: :container, schema: Fixtures.SszTestTypes.Foo}},
    %{
      list_a: %{
        type: :list,
        schema: %{type: :container, schema: Fixtures.SszTestTypes.Foo},
        max_size: 1
      }
    },
    %{field_static_c: %{type: :bytes, size: 48}},
    %{int_a: %{type: :uint, size: 32}},
    %{vec_a: %{type: :vector, schema: %{type: :uint, size: 8}, max_size: 33}}
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          field_static_a: SszTypes.bytes32(),
          container_static_b: Fixtures.SszTestTypes.Foo.t(),
          list_a: list(Fixtures.SszTestTypes.Foo.t()),
          field_static_c: SszTypes.bls_pubkey(),
          int_a: SszTypes.uint32(),
          vec_a: list(SszTypes.uint8())
        }
  def schema, do: @schema
end
