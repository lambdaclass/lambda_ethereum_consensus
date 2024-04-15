defmodule SszEx do
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
  alias SszEx.Decode
  alias SszEx.Encode
  alias SszEx.Hash
  alias SszEx.Merkleization
  alias SszEx.Utils

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

  @spec encode(struct()) ::
          {:ok, binary()} | {:error, String.t()}
  def encode(%name{} = value), do: encode(value, name)

  @spec encode(any(), schema()) ::
          {:ok, binary()} | {:error, String.t()}
  def encode(value, schema), do: Encode.encode(value, schema)

  @spec decode(binary(), schema()) ::
          {:ok, any()} | {:error, String.t()}
  def decode(value, schema), do: Decode.decode(value, schema)

  @spec hash_tree_root!(struct()) :: Types.root()
  def hash_tree_root!(%name{} = value), do: hash_tree_root!(value, name)

  @spec hash_tree_root!(any, any) :: Types.root()
  def hash_tree_root!(value, schema), do: Merkleization.hash_tree_root!(value, schema)

  @spec hash_tree_root(any, any) :: {:ok, Types.root()} | {:error, String.t()}
  def hash_tree_root(value, schema), do: Merkleization.hash_tree_root(value, schema)

  @spec validate_schema!(any) :: :ok
  def validate_schema!(schema), do: Utils.validate_schema!(schema)

  @spec default(any) :: any()
  def default(schema), do: Utils.default(schema)

  @spec hash(iodata()) :: binary()
  def hash(data), do: Hash.hash(data)

  @spec hash_nodes(binary(), binary()) :: binary()
  def hash_nodes(left, right), do: Hash.hash_nodes(left, right)

  @spec get_zero_hash(non_neg_integer()) :: binary()
  def get_zero_hash(depth), do: Merkleization.get_zero_hash(depth)
end
