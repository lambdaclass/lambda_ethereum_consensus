defmodule LambdaEthereumConsensus.SszEx do
  @moduledoc """
    # SSZ library in Elixir
    ## Schema
    The schema is a recursive data structure that describes the structure of the data to be encoded/decoded.
    It can be one of the following:

    - `{:int, bits}`
      Basic type. N-bit unsigned integer, where `bits` is one of: 8, 16, 32, 64, 128, 256
    - `:bool`
      Basic type. True or False
    - `{:list, inner_type, max_length}`
      Composite type of ordered homogeneous elements, with a max length of `max_length`.
      `inner_type` is the schema of the inner elements. Depending on it, the list could be
      variable-size or fixed-size.
    - `{:vector, inner_type, length}`
      Composite type of ordered homogeneous elements with an exact number of elements (`length`).
      `inner_type` is the schema of the inner elements. Depending on it, the vector could be
      <!-- variable-size or fixed-size. -->
    - `{:byte_list, max_length}`
      Same as `{:list, {:int, 8}, length}` (i.e. a list of bytes), but
      encodes-from/decodes-into an Elixir binary.
    - `{:byte_vector, length}`
      Same as `{:vector, {:int, 8}, length}` (i.e. a vector of bytes),
      but encodes-from/decodes-into an Elixir binary.
    - `{:bitlist, max_length}`
      Composite type. A more efficient format for `{:list, :bool, max_length}`.
      Expects the input to be a `BitList`.
    - `{:bitvector, length}`
      Composite type. A more efficient format for `{:vector, :bool, max_length}`.
      Expects the input to be a `BitVector`.
    - `container`
      Where `container` is a module that implements the `LambdaEthereumConsensus.Container` behaviour.
      Expects the input to be an Elixir struct.
  """

  @type schema() ::
          :bool
          | uint_schema()
          | byte_list_schema()
          | byte_vector_schema()
          | list_schema()
          | vector_schema()
          | bitlist_schema()
          | bitvector_schema()
          | container_schema()

  @type uint_schema() :: {:int, 8 | 16 | 32 | 64 | 128 | 256}
  @type byte_list_schema() :: {:byte_list, max_size :: non_neg_integer}
  @type byte_vector_schema() :: {:byte_vector, size :: non_neg_integer}
  @type list_schema() :: {:list, schema(), max_size :: non_neg_integer}
  @type vector_schema() :: {:vector, schema(), size :: non_neg_integer}
  @type bitlist_schema() :: {:bitlist, max_size :: non_neg_integer}
  @type bitvector_schema() :: {:bitvector, size :: non_neg_integer}
  @type container_schema() :: module()
end
