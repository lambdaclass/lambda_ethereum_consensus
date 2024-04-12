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
      variable-size or fixed-size.
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
  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Utils.BitVector
  alias LambdaEthereumConsensus.Utils.ZeroHashes

  import Aja
  import BitVector
  import Bitwise

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

  #################
  ### Public API
  #################
  import Bitwise

  @allowed_uints [8, 16, 32, 64, 128, 256]
  @bytes_per_chunk 32
  @bits_per_byte 8
  @bits_per_chunk @bytes_per_chunk * @bits_per_byte
  @zero_chunk <<0::size(@bits_per_chunk)>>

  @compile {:inline, hash: 1}
  @spec hash(iodata()) :: binary()
  def hash(data), do: :crypto.hash(:sha256, data)

  @spec hash_nodes(binary(), binary()) :: binary()
  def hash_nodes(left, right), do: :crypto.hash(:sha256, left <> right)

  @zero_hashes ZeroHashes.compute_zero_hashes()

  @spec get_zero_hash(0..64) :: binary()
  def get_zero_hash(depth), do: ZeroHashes.get_zero_hash(depth, @zero_hashes)

  @spec validate_schema!(schema()) :: :ok
  def validate_schema!(:bool), do: :ok
  def validate_schema!({:int, n}) when n in @allowed_uints, do: :ok
  def validate_schema!({:byte_list, size}) when size > 0, do: :ok
  def validate_schema!({:byte_vector, size}) when size > 0, do: :ok
  def validate_schema!({:list, sub, size}) when size > 0, do: validate_schema!(sub)
  def validate_schema!({:vector, sub, size}) when size > 0, do: validate_schema!(sub)
  def validate_schema!({:bitlist, size}) when size > 0, do: :ok
  def validate_schema!({:bitvector, size}) when size > 0, do: :ok

  def validate_schema!(module) when is_atom(module) do
    schema = module.schema()
    # validate each sub-schema
    {fields, subschemas} = Enum.unzip(schema)
    Enum.each(subschemas, &validate_schema!/1)

    # check the struct field names match the schema keys
    struct_fields =
      module.__struct__() |> Map.keys() |> MapSet.new() |> MapSet.delete(:__struct__)

    fields = MapSet.new(fields)

    if MapSet.equal?(fields, struct_fields) do
      :ok
    else
      missing =
        MapSet.symmetric_difference(fields, struct_fields)
        |> Enum.map_join(", ", &inspect/1)

      raise "The struct and its schema differ by some fields: #{missing}"
    end
  end

  @spec encode(any(), schema()) :: {:ok, binary()} | {:error, String.t()}
  def encode(value, {:int, size}), do: encode_int(value, size)
  def encode(value, :bool), do: encode_bool(value)
  def encode(value, {:byte_list, _}), do: {:ok, value}
  def encode(value, {:byte_vector, _}), do: {:ok, value}

  def encode(list, {:list, inner_type, size}) do
    if variable_size?(inner_type),
      do: encode_variable_size_list(list, inner_type, size),
      else: encode_fixed_size_list(list, inner_type, size)
  end

  def encode(vector, {:vector, inner_type, size}) do
    if variable_size?(inner_type),
      do: encode_variable_size_list(vector, inner_type, size),
      else: encode_fixed_size_list(vector, inner_type, size)
  end

  def encode(value, {:bitlist, max_size}) when is_bitstring(value),
    do: encode_bitlist(value, max_size)

  def encode(value, {:bitlist, max_size}) when is_integer(value),
    do: encode_bitlist(:binary.encode_unsigned(value), max_size)

  def encode(value, {:bitvector, size}) when is_bitvector(value),
    do: encode_bitvector(value, size)

  def encode(container, module) when is_map(container),
    do: encode_container(container, module.schema())

  @spec decode(binary(), schema()) :: {:ok, any()} | {:error, String.t()}
  def decode(binary, :bool), do: decode_bool(binary)
  def decode(binary, {:int, size}), do: decode_uint(binary, size)
  def decode(value, {:byte_list, _}), do: {:ok, value}
  def decode(value, {:byte_vector, _}), do: {:ok, value}

  def decode(binary, {:list, inner_type, size}) do
    if variable_size?(inner_type),
      do: decode_variable_list(binary, inner_type, size),
      else: decode_fixed_list(binary, inner_type, size)
  end

  def decode(binary, {:vector, inner_type, size}) do
    if variable_size?(inner_type),
      do: decode_variable_list(binary, inner_type, size),
      else: decode_fixed_vector(binary, inner_type, size)
  end

  def decode(value, {:bitlist, max_size}) when is_bitstring(value),
    do: decode_bitlist(value, max_size)

  def decode(value, {:bitvector, size}) when is_bitstring(value),
    do: decode_bitvector(value, size)

  def decode(binary, module) when is_atom(module) do
    with {:ok, result} <-
           if(variable_size?(module),
             do: decode_variable_container(binary, module),
             else: decode_fixed_container(binary, module)
           ) do
      if exported?(module, :decode_ex, 1) do
        {:ok, module.decode_ex(result)}
      else
        {:ok, result}
      end
    end
  end

  @spec hash_tree_root!(struct()) :: Types.root()
  def hash_tree_root!(%name{} = value) do
    {:ok, root} = hash_tree_root(value, name)
    root
  end

  @spec hash_tree_root!(any, any) :: Types.root()
  def hash_tree_root!(value, schema) do
    {:ok, root} = hash_tree_root(value, schema)
    root
  end

  @spec hash_tree_root(boolean, atom) :: {:ok, Types.root()}
  def hash_tree_root(value, :bool), do: {:ok, pack(value, :bool)}

  @spec hash_tree_root(non_neg_integer, {:int, non_neg_integer}) :: {:ok, Types.root()}
  def hash_tree_root(value, {:int, size}), do: {:ok, pack(value, {:int, size})}

  @spec hash_tree_root(binary, {:byte_list, non_neg_integer}) :: {:ok, Types.root()}
  def hash_tree_root(value, {:byte_list, _size} = schema) do
    chunks = value |> pack_bytes()
    limit = chunk_count(schema)
    hash_tree_root_list(chunks, limit, value |> byte_size())
  end

  @spec hash_tree_root(binary, {:byte_vector, non_neg_integer}) ::
          {:ok, Types.root()}
  def hash_tree_root(value, {:byte_vector, _size}) do
    packed_chunks = pack_bytes(value)
    leaf_count = packed_chunks |> get_chunks_len() |> next_pow_of_two()
    root = merkleize_chunks_with_virtual_padding(packed_chunks, leaf_count)
    {:ok, root}
  end

  @spec hash_tree_root(binary, {:bitlist | :bitvector, non_neg_integer}) :: {:ok, Types.root()}
  def hash_tree_root(value, {type, _size} = schema) when type in [:bitlist, :bitvector] do
    chunks = value |> pack_bits(type)
    leaf_count = chunk_count(schema) |> next_pow_of_two()
    root = chunks |> merkleize_chunks_with_virtual_padding(leaf_count)

    root =
      if type == :bitlist do
        len = value |> bit_size()
        root |> mix_in_length(len)
      else
        root
      end

    {:ok, root}
  end

  def hash_tree_root(vec(_) = list, {:list, _any, _non_neg_integer} = schema) do
    list
    |> Aja.Vector.to_list()
    |> hash_tree_root(schema)
  end

  @spec hash_tree_root(list(), {:list, any, non_neg_integer}) ::
          {:ok, Types.root()} | {:error, String.t()}
  def hash_tree_root(list, {:list, type, _size} = schema) do
    limit = chunk_count(schema)
    len = length(list)

    value =
      if basic_type?(type) do
        pack(list, schema)
      else
        list_hash_tree_root(list, type)
      end

    case value do
      {:ok, chunks} -> chunks |> hash_tree_root_list(limit, len)
      {:error, reason} -> {:error, reason}
      chunks -> chunks |> hash_tree_root_list(limit, len)
    end
  end

  @spec hash_tree_root(list(), {:vector, any, non_neg_integer}) ::
          {:ok, Types.root()} | {:error, String.t()}
  def hash_tree_root(vector, {:vector, _type, size}) when length(vector) != size,
    do: {:error, "invalid size"}

  def hash_tree_root(vector, {:vector, type, _size} = schema) do
    value =
      if basic_type?(type) do
        pack(vector, schema)
      else
        list_hash_tree_root(vector, type)
      end

    case value do
      {:ok, chunks} -> chunks |> hash_tree_root_vector()
      {:error, reason} -> {:error, reason}
      chunks -> chunks |> hash_tree_root_vector()
    end
  end

  @spec hash_tree_root(struct(), atom()) :: {:ok, Types.root()}
  def hash_tree_root(container, module) when is_map(container) do
    value =
      module.schema()
      |> Enum.reduce_while({:ok, <<>>}, fn {key, schema}, {_, acc_root} ->
        value = container |> Map.get(key)

        case hash_tree_root(value, schema) do
          {:ok, root} -> {:cont, {:ok, acc_root <> root}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case value do
      {:ok, chunks} ->
        leaf_count =
          chunks |> get_chunks_len() |> next_pow_of_two()

        root = chunks |> merkleize_chunks_with_virtual_padding(leaf_count)
        {:ok, root}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def hash_tree_root_vector(chunks) do
    leaf_count = chunks |> get_chunks_len() |> next_pow_of_two()
    root = merkleize_chunks_with_virtual_padding(chunks, leaf_count)
    {:ok, root}
  end

  def hash_tree_root_list(chunks, limit, len) do
    chunks_len = chunks |> get_chunks_len()

    if chunks_len > limit do
      {:error, "chunk size exceeds limit"}
    else
      root = merkleize_chunks_with_virtual_padding(chunks, limit) |> mix_in_length(len)
      {:ok, root}
    end
  end

  @spec mix_in_length(Types.root(), non_neg_integer) :: Types.root()
  def mix_in_length(root, len) do
    {:ok, serialized_len} = encode_int(len, @bits_per_chunk)
    root |> hash_nodes(serialized_len)
  end

  # Currently, we are not using this one.
  def merkleize_chunks(chunks, leaf_count \\ nil) do
    chunks_len = chunks |> get_chunks_len()

    if chunks_len == 1 and leaf_count == nil do
      chunks
    else
      power = leaf_count |> compute_pow()
      height = power + 1
      first_layer = chunks |> convert_to_next_pow_of_two(leaf_count)

      final_layer =
        1..(height - 1)
        |> Enum.reverse()
        |> Enum.reduce(first_layer, fn _i, acc_layer ->
          get_parent_layer(acc_layer)
        end)

      final_layer
    end
  end

  def merkleize_chunks_with_virtual_padding(chunks, leaf_count) do
    chunks_len = chunks |> get_chunks_len()
    power = leaf_count |> compute_pow()
    height = power + 1

    cond do
      chunks_len == 0 ->
        depth = height - 1
        get_zero_hash(depth)

      chunks_len == 1 and leaf_count == 1 ->
        chunks

      true ->
        first_layer = chunks
        last_index = chunks_len - 1

        {_, final_layer} =
          1..(height - 1)
          |> Enum.reverse()
          |> Enum.reduce({last_index, first_layer}, fn i, {current_last_index, current_layer} ->
            parent_layers = get_parent_layer(i, height, current_layer, current_last_index)
            {current_last_index |> div(2), parent_layers}
          end)

        <<root::binary-size(@bytes_per_chunk), _::binary>> = final_layer
        root
    end
  end

  @spec pack(boolean, :bool) :: binary()
  def pack(true, :bool), do: <<1::@bits_per_chunk-little>>
  def pack(false, :bool), do: @zero_chunk

  @spec pack(non_neg_integer, {:int, non_neg_integer}) :: binary()
  def pack(value, {:int, size}) do
    <<value::size(size)-little>> |> pack_bytes()
  end

  @spec pack(list(), {:list | :vector, any, non_neg_integer}) :: binary() | :error
  def pack(list, {type, schema, _}) when type in [:vector, :list] do
    list
    |> Enum.reduce(<<>>, fn x, acc ->
      {:ok, encoded} = encode(x, schema)
      acc <> encoded
    end)
    |> pack_bytes()
  end

  def pack_bits(value, :bitvector) do
    BitVector.to_bytes(value) |> pack_bytes()
  end

  def pack_bits(value, :bitlist) do
    value |> BitList.to_packed_bytes() |> pack_bytes()
  end

  def chunk_count({:list, type, max_size}) do
    if basic_type?(type) do
      size = size_of(type)
      (max_size * size + 31) |> div(32)
    else
      max_size
    end
  end

  def chunk_count({:byte_list, max_size}), do: (max_size + 31) |> div(32)

  def chunk_count({identifier, size}) when identifier in [:bitlist, :bitvector] do
    (size + @bits_per_chunk - 1) |> div(@bits_per_chunk)
  end

  @doc """
  Returns the default value for a schema, which can be a basic or composite type.
  """
  def default({:int, _}), do: 0
  def default(:bool), do: false
  def default({:byte_list, _size}), do: <<>>
  def default({:byte_vector, size}), do: <<0::size(size * 8)>>
  def default({:list, _, _}), do: []
  def default({:vector, inner_type, size}), do: default(inner_type) |> List.duplicate(size)
  def default({:bitlist, _}), do: BitList.default()
  def default({:bitvector, size}), do: BitVector.new(size)

  def default(module) when is_atom(module) do
    module.schema()
    |> Enum.map(fn {attr, schema} -> {attr, default(schema)} end)
    |> then(&struct!(module, &1))
  end

  #################
  ### Private functions
  #################
  @bytes_per_boolean 4
  @bytes_per_length_offset 4
  @offset_bits 32

  defp encode_int(value, size) when is_integer(value), do: {:ok, <<value::size(size)-little>>}
  defp encode_bool(true), do: {:ok, "\x01"}
  defp encode_bool(false), do: {:ok, "\x00"}

  defp decode_uint(binary, size) when bit_size(binary) == size do
    <<element::integer-size(size)-little, _rest::bitstring>> = binary
    {:ok, element}
  end

  defp decode_uint(_binary, size), do: {:error, "invalid byte size #{inspect(size)}"}

  defp decode_bool("\x01"), do: {:ok, true}
  defp decode_bool("\x00"), do: {:ok, false}
  defp decode_bool(_), do: {:error, "invalid bool value"}

  defp encode_fixed_size_list(vec(_) = list, inner_type, size) do
    encode_fixed_size_list(Aja.Vector.to_list(list), inner_type, size)
  end

  defp encode_fixed_size_list(list, _inner_type, max_size) when length(list) > max_size,
    do: {:error, "invalid max_size of list"}

  defp encode_fixed_size_list(list, inner_type, _size) when is_list(list) do
    list
    |> Enum.map(&encode(&1, inner_type))
    |> flatten_results_by(&Enum.join/1)
  end

  defp encode_bitlist(bit_list, max_size) do
    len = bit_size(bit_list)

    if len > max_size do
      {:error, "excess bits"}
    else
      {:ok, BitList.to_bytes(bit_list)}
    end
  end

  defp encode_bitvector(bit_vector, size) when bit_vector_size(bit_vector) == size,
    do: {:ok, BitVector.to_bytes(bit_vector)}

  defp encode_bitvector(_bit_vector, _size), do: {:error, "invalid bit_vector length"}

  defp encode_variable_size_list(vec(_) = list, inner_type, max_size) do
    encode_variable_size_list(Aja.Vector.to_list(list), inner_type, max_size)
  end

  defp encode_variable_size_list(list, _inner_type, max_size) when length(list) > max_size,
    do: {:error, "invalid max_size of list"}

  defp encode_variable_size_list(list, inner_type, _size) when is_list(list) do
    fixed_lengths = @bytes_per_length_offset * length(list)

    with {:ok, {encoded_variable_parts, variable_offsets_list, total_byte_size}} <-
           encode_variable_parts(list, inner_type),
         :ok <- check_length(fixed_lengths, total_byte_size),
         {variable_offsets, _} =
           Enum.reduce(variable_offsets_list, {[], 0}, fn element, {res, acc} ->
             sum = fixed_lengths + acc
             {[sum | res], element + acc}
           end),
         {:ok, encoded_variable_offsets} <-
           variable_offsets
           |> Enum.reverse()
           |> Enum.map(&encode(&1, {:int, 32}))
           |> flatten_results() do
      (encoded_variable_offsets ++ encoded_variable_parts)
      |> :binary.list_to_bin()
      |> then(&{:ok, &1})
    end
  end

  defp encode_variable_parts(list, inner_type) do
    with {:ok, {encoded_list, byte_size_list, total_byte_size}} <-
           Enum.reduce_while(list, {:ok, {[], [], 0}}, fn value,
                                                          {:ok, {res_encoded, res_size, acc}} ->
             case encode(value, inner_type) do
               {:ok, encoded} ->
                 size = byte_size(encoded)
                 {:cont, {:ok, {[encoded | res_encoded], [size | res_size], size + acc}}}

               error ->
                 {:halt, {:error, error}}
             end
           end) do
      {:ok, {Enum.reverse(encoded_list), Enum.reverse(byte_size_list), total_byte_size}}
    end
  end

  defp decode_bitlist(bit_list, max_size) when bit_size(bit_list) > 0 do
    num_bytes = byte_size(bit_list)
    decoded = BitList.new(bit_list)
    len = BitList.length(decoded)

    cond do
      match?(<<_::binary-size(num_bytes - 1), 0>>, bit_list) ->
        {:error, "BitList has no length information."}

      div(len, @bits_per_byte) + 1 != num_bytes ->
        {:error, "invalid byte count"}

      len > max_size ->
        {:error, "out of bounds"}

      true ->
        {:ok, decoded}
    end
  end

  defp decode_bitlist(_bit_list, _max_size), do: {:error, "invalid bitlist"}

  defp decode_bitvector(bit_vector, size) do
    num_bytes = byte_size(bit_vector)

    cond do
      bit_size(bit_vector) == 0 ->
        {:error, "ExcessBits"}

      num_bytes != max(1, div(size + 7, 8)) ->
        {:error, "InvalidByteCount"}

      true ->
        case bit_vector do
          # Padding bits are clear
          <<_first::binary-size(num_bytes - 1), 0::size(8 - rem(size, 8) &&& 7),
            _rest::bitstring>> ->
            {:ok, BitVector.new(bit_vector, size)}

          _else ->
            {:error, "ExcessBits"}
        end
    end
  end

  defp decode_fixed_list(binary, inner_type, size) do
    fixed_size = get_fixed_size(inner_type)

    with {:ok, decoded_list} = result <- decode_fixed_collection(binary, fixed_size, inner_type),
         :ok <- check_valid_list_size_after_decode(size, length(decoded_list)) do
      result
    end
  end

  defp decode_fixed_vector(binary, inner_type, size) do
    fixed_size = get_fixed_size(inner_type)

    with :ok <- check_valid_vector_size_prev_decode(fixed_size, size, binary),
         {:ok, decoded_vector} = result <-
           decode_fixed_collection(binary, fixed_size, inner_type),
         :ok <- check_valid_vector_size_after_decode(size, length(decoded_vector)) do
      result
    end
  end

  def check_valid_vector_size_prev_decode(fixed_size, size, binary)
      when fixed_size * size == byte_size(binary),
      do: :ok

  def check_valid_vector_size_prev_decode(_fixed_size, _size, _binary),
    do: {:error, "Invalid vector size"}

  def check_valid_vector_size_after_decode(size, decoded_size)
      when decoded_size == size and decoded_size > 0,
      do: :ok

  def check_valid_vector_size_after_decode(_size, _decoded_size),
    do: {:error, "invalid vector decoded size"}

  def check_valid_list_size_after_decode(size, decoded_size) when decoded_size <= size, do: :ok

  def check_valid_list_size_after_decode(_size, _decoded_size),
    do: {:error, "invalid max_size of list"}

  defp decode_variable_list(binary, _, _) when byte_size(binary) == 0 do
    {:ok, []}
  end

  defp decode_variable_list(
         <<first_offset::integer-32-little, _rest_bytes::bitstring>>,
         _inner_type,
         size
       )
       when div(first_offset, @bytes_per_length_offset) > size,
       do: {:error, "invalid length list"}

  defp decode_variable_list(binary, inner_type, _size) do
    <<first_offset::integer-32-little, rest_bytes::bitstring>> = binary
    num_elements = div(first_offset, @bytes_per_length_offset)

    if Integer.mod(first_offset, @bytes_per_length_offset) != 0 ||
         first_offset < @bytes_per_length_offset do
      {:error, "InvalidListFixedBytesLen"}
    else
      with :ok <-
             sanitize_offset(first_offset, nil, byte_size(binary), first_offset) do
        decode_variable_list_elements(
          num_elements,
          rest_bytes,
          inner_type,
          first_offset,
          binary,
          first_offset,
          []
        )
        |> Enum.reverse()
        |> flatten_results()
      end
    end
  end

  defp decode_variable_list_elements(
         1 = _num_elements,
         _acc_rest_bytes,
         inner_type,
         offset,
         binary,
         _first_offset,
         results
       ) do
    part = :binary.part(binary, offset, byte_size(binary) - offset)
    [decode(part, inner_type) | results]
  end

  defp decode_variable_list_elements(
         num_elements,
         acc_rest_bytes,
         inner_type,
         offset,
         binary,
         first_offset,
         results
       ) do
    <<next_offset::integer-32-little, rest_bytes::bitstring>> = acc_rest_bytes

    with :ok <-
           sanitize_offset(next_offset, offset, byte_size(binary), first_offset) do
      part = :binary.part(binary, offset, next_offset - offset)

      decode_variable_list_elements(
        num_elements - 1,
        rest_bytes,
        inner_type,
        next_offset,
        binary,
        first_offset,
        [decode(part, inner_type) | results]
      )
    end
  end

  defp encode_container(container, schemas) do
    {fixed_size_values, fixed_length, variable_values} = analyze_schemas(container, schemas)

    with {:ok, variable_parts} <- encode_schemas(Enum.reverse(variable_values)),
         offsets = calculate_offsets(variable_parts, fixed_length),
         variable_length =
           Enum.reduce(variable_parts, 0, fn part, acc -> byte_size(part) + acc end),
         :ok <- check_length(fixed_length, variable_length),
         {:ok, fixed_parts} <-
           replace_offsets(fixed_size_values, offsets)
           |> encode_schemas() do
      (fixed_parts ++ variable_parts)
      |> Enum.join()
      |> then(&{:ok, &1})
    end
  end

  defp analyze_schemas(container, schemas) do
    schemas
    |> Enum.reduce({[], 0, []}, fn {key, schema},
                                   {acc_fixed_size_values, acc_fixed_length, acc_variable_values} ->
      value = Map.fetch!(container, key)

      if variable_size?(schema) do
        {[:offset | acc_fixed_size_values], @bytes_per_length_offset + acc_fixed_length,
         [{value, schema} | acc_variable_values]}
      else
        {[{value, schema} | acc_fixed_size_values], acc_fixed_length + get_fixed_size(schema),
         acc_variable_values}
      end
    end)
  end

  defp encode_schemas(tuple_values) do
    Enum.map(tuple_values, fn {value, schema} -> encode(value, schema) end)
    |> flatten_results()
  end

  defp calculate_offsets(variable_parts, fixed_length) do
    {offsets, _} =
      Enum.reduce(variable_parts, {[], fixed_length}, fn element, {res, acc} ->
        {[{acc, {:int, 32}} | res], byte_size(element) + acc}
      end)

    offsets
  end

  defp replace_offsets(fixed_size_values, offsets) do
    {fixed_size_values, _} =
      Enum.reduce(fixed_size_values, {[], offsets}, &replace_offset/2)

    fixed_size_values
  end

  defp replace_offset(:offset, {acc_fixed_list, [offset | rest_offsets]}),
    do: {[offset | acc_fixed_list], rest_offsets}

  defp replace_offset(element, {acc_fixed_list, acc_offsets_list}),
    do: {[element | acc_fixed_list], acc_offsets_list}

  defp decode_variable_container(binary, module) do
    schemas = module.schema()
    fixed_length = get_fixed_length(schemas)

    with :ok <- sanitize_offset(fixed_length, nil, byte_size(binary), nil),
         <<fixed_binary::binary-size(fixed_length), variable_binary::bitstring>> = binary,
         {:ok, fixed_parts, offsets, items_index} <-
           decode_fixed_section(fixed_binary, schemas, fixed_length),
         :ok <- check_first_offset(offsets, items_index, byte_size(binary)),
         {:ok, variable_parts} <- decode_variable_section(binary, variable_binary, offsets) do
      {:ok, struct!(module, fixed_parts ++ variable_parts)}
    end
  end

  defp decode_fixed_container(binary, module) do
    schemas = module.schema()
    fixed_length = get_fixed_length(schemas)

    with {:ok, fixed_parts, _offsets, items_index} <-
           decode_fixed_section(binary, schemas, fixed_length),
         :ok <- check_byte_len(items_index, byte_size(binary)) do
      {:ok, struct!(module, fixed_parts)}
    end
  end

  defp check_first_offset([{offset, _} | _rest], items_index, _binary_size) do
    cond do
      offset < items_index -> {:error, "OffsetIntoFixedPortion (#{offset})"}
      offset > items_index -> {:error, "OffsetSkipsVariableBytes"}
      true -> :ok
    end
  end

  defp check_byte_len(items_index, binary_size)
       when items_index == binary_size,
       do: :ok

  defp check_byte_len(_items_index, _binary_size),
    do: {:error, "InvalidByteLength"}

  defp decode_variable_section(full_binary, binary, offsets) do
    offsets
    |> Enum.chunk_every(2, 1)
    |> Enum.reduce_while({binary, []}, fn
      [{offset, {key, schema}}, {next_offset, _}], {rest_bytes, acc_variable_parts} ->
        case sanitize_offset(next_offset, offset, byte_size(full_binary), nil) do
          :ok ->
            size = next_offset - offset
            <<chunk::binary-size(size), rest::bitstring>> = rest_bytes
            {:cont, {rest, [{key, decode(chunk, schema)} | acc_variable_parts]}}

          error ->
            {:halt, {<<>>, [{key, error} | acc_variable_parts]}}
        end

      [{_offset, {key, schema}}], {rest_bytes, acc_variable_parts} ->
        {:cont, {<<>>, [{key, decode(rest_bytes, schema)} | acc_variable_parts]}}
    end)
    |> then(fn {<<>>, variable_parts} ->
      flatten_container_results(variable_parts)
    end)
  end

  defp decode_fixed_section(binary, schemas, _fixed_length) do
    schemas
    |> Enum.reduce({binary, [], [], 0}, fn {key, schema},
                                           {binary, fixed_parts, offsets, items_index} ->
      if variable_size?(schema) do
        <<offset::integer-size(@offset_bits)-little, rest::bitstring>> = binary

        {rest, fixed_parts, [{offset, {key, schema}} | offsets],
         items_index + @bytes_per_length_offset}
      else
        ssz_fixed_len = get_fixed_size(schema)
        <<chunk::binary-size(ssz_fixed_len), rest::bitstring>> = binary
        {rest, [{key, decode(chunk, schema)} | fixed_parts], offsets, items_index + ssz_fixed_len}
      end
    end)
    |> then(fn {_rest_bytes, fixed_parts, offsets, items_index} ->
      Tuple.append(flatten_container_results(fixed_parts), Enum.reverse(offsets))
      |> Tuple.append(items_index)
    end)
  end

  defp get_fixed_length(schemas) do
    schemas
    |> Stream.map(fn {_key, schema} ->
      if variable_size?(schema) do
        @bytes_per_length_offset
      else
        get_fixed_size(schema)
      end
    end)
    |> Enum.sum()
  end

  # https://notes.ethereum.org/ruKvDXl6QOW3gnqVYb8ezA?view
  defp sanitize_offset(offset, previous_offset, num_bytes, nil) do
    cond do
      offset > num_bytes ->
        {:error, "OffsetOutOfBounds"}

      previous_offset != nil && previous_offset > offset ->
        {:error, "OffsetsAreDecreasing"}

      true ->
        :ok
    end
  end

  defp sanitize_offset(offset, previous_offset, _num_bytes, num_fixed_bytes) do
    cond do
      offset < num_fixed_bytes ->
        {:error, "OffsetIntoFixedPortion #{offset}"}

      previous_offset == nil && offset != num_fixed_bytes ->
        {:error, "OffsetSkipsVariableBytes"}

      true ->
        :ok
    end
  end

  defp decode_fixed_collection(binary, chunk_size, inner_type) do
    decode_fixed_collection(binary, chunk_size, inner_type, [])
    |> Enum.reverse()
    |> flatten_results()
  end

  defp decode_fixed_collection(<<>>, _chunk_size, _inner_type, results), do: results

  defp decode_fixed_collection(binary, chunk_size, _inner_type, results)
       when byte_size(binary) < chunk_size,
       do: [{:error, "InvalidByteLength"} | results]

  defp decode_fixed_collection(binary, chunk_size, inner_type, results) do
    <<element::binary-size(chunk_size), rest::bitstring>> = binary
    decode_fixed_collection(rest, chunk_size, inner_type, [decode(element, inner_type) | results])
  end

  defp flatten_results(results) do
    flatten_results_by(results, &Function.identity/1)
  end

  defp flatten_results_by(results, fun) do
    case Enum.group_by(results, fn {type, _} -> type end, fn {_, result} -> result end) do
      %{error: errors} -> {:error, errors}
      summary -> {:ok, fun.(Map.get(summary, :ok, []))}
    end
  end

  defp flatten_container_results(results) do
    case Enum.group_by(results, fn {_, {type, _}} -> type end, fn {key, {_, result}} ->
           {key, result}
         end) do
      %{error: errors} -> {:error, errors}
      summary -> {:ok, Map.get(summary, :ok, [])}
    end
  end

  defp check_length(fixed_lengths, total_byte_size) do
    if fixed_lengths + total_byte_size <
         2 ** (@bytes_per_length_offset * @bits_per_byte) do
      :ok
    else
      {:error, "invalid lengths"}
    end
  end

  defp get_fixed_size(:bool), do: 1
  defp get_fixed_size({:int, size}), do: div(size, @bits_per_byte)
  defp get_fixed_size({:byte_vector, size}), do: size
  defp get_fixed_size({:vector, inner_type, size}), do: size * get_fixed_size(inner_type)
  defp get_fixed_size({:bitvector, size}), do: div(size + 7, 8)

  defp get_fixed_size(module) when is_atom(module) do
    schemas = module.schema()

    schemas
    |> Enum.map(fn {_, schema} -> get_fixed_size(schema) end)
    |> Enum.sum()
  end

  defp variable_size?({:list, _, _}), do: true
  defp variable_size?(:bool), do: false
  defp variable_size?({:byte_list, _}), do: true
  defp variable_size?({:byte_vector, _}), do: false
  defp variable_size?({:int, _}), do: false
  defp variable_size?({:bitlist, _}), do: true
  defp variable_size?({:bitvector, _}), do: false
  defp variable_size?({:vector, inner_type, _}), do: variable_size?(inner_type)

  defp variable_size?(module) when is_atom(module) do
    module.schema()
    |> Enum.map(fn {_, schema} -> variable_size?(schema) end)
    |> Enum.any?()
  end

  defp basic_type?({:int, _}), do: true
  defp basic_type?(:bool), do: true
  defp basic_type?({:list, _, _}), do: false
  defp basic_type?({:vector, _, _}), do: false
  defp basic_type?({:bitlist, _}), do: false
  defp basic_type?({:bitvector, _}), do: false
  defp basic_type?({:byte_list, _}), do: false
  defp basic_type?({:byte_vector, _}), do: false
  defp basic_type?(module) when is_atom(module), do: false

  defp size_of(:bool), do: @bytes_per_boolean

  defp size_of({:int, size}), do: size |> div(@bits_per_byte)

  defp pack_bytes(value) when is_binary(value) do
    incomplete_chunk_len = value |> bit_size() |> rem(@bits_per_chunk)

    if incomplete_chunk_len != 0 do
      pad = @bits_per_chunk - incomplete_chunk_len
      <<value::binary, 0::size(pad)>>
    else
      value
    end
  end

  defp convert_to_next_pow_of_two(chunks, leaf_count) do
    size = chunks |> byte_size() |> div(@bytes_per_chunk)
    next_pow = leaf_count |> next_pow_of_two()

    if size == next_pow do
      chunks
    else
      diff = next_pow - size
      zero_chunks = 0..(diff - 1) |> Enum.reduce(<<>>, fn _, acc -> <<0::256>> <> acc end)
      chunks <> zero_chunks
    end
  end

  defp next_pow_of_two(0), do: 0

  defp next_pow_of_two(len) when is_integer(len) and len > 0 do
    n = ((len <<< 1) - 1) |> compute_pow()
    2 ** n
  end

  defp get_chunks_len(chunks) do
    chunks |> byte_size() |> div(@bytes_per_chunk)
  end

  defp compute_pow(value) do
    :math.log2(value) |> trunc()
  end

  defp get_parent_layer(i, height, current_layer, current_last_index) do
    0..current_last_index
    |> Enum.filter(fn x -> rem(x, 2) == 0 end)
    |> Enum.reduce(<<>>, fn j, acc_parent_layer ->
      {left, right} = get_nodes(i, j, height, current_layer, current_last_index)
      acc_parent_layer <> hash_nodes(left, right)
    end)
  end

  defp get_parent_layer(current_layer) do
    0..(get_chunks_len(current_layer) - 1)
    |> Enum.filter(fn x -> rem(x, 2) == 0 end)
    |> Enum.reduce(<<>>, fn j, acc_parent_layer ->
      {left, right} = get_nodes(j, current_layer)
      acc_parent_layer <> hash_nodes(left, right)
    end)
  end

  defp get_nodes(left_children_index, current_layer) do
    children = extract_chunks(left_children_index, current_layer, 2)

    <<left::binary-size(@bytes_per_chunk), right::binary-size(@bytes_per_chunk)>> =
      children

    {left, right}
  end

  defp get_nodes(_i, left_children_index, _height, current_layer, current_last_index)
       when left_children_index < current_last_index do
    get_nodes(left_children_index, current_layer)
  end

  defp get_nodes(i, left_children_index, height, current_layer, current_last_index)
       when left_children_index == current_last_index do
    left = extract_chunks(left_children_index, current_layer, 1)
    depth = height - i - 1
    right = get_zero_hash(depth)
    {left, right}
  end

  def extract_chunks(left_chunk_index, chunks, chunk_count) do
    start = left_chunk_index * @bytes_per_chunk
    stop = (left_chunk_index + chunk_count) * @bytes_per_chunk
    extracted_chunks = chunks |> :binary.part(start, stop - start)
    extracted_chunks
  end

  def list_hash_tree_root(list, inner_schema) do
    list
    |> Enum.reduce_while({:ok, <<>>}, fn value, {_, acc_roots} ->
      case hash_tree_root(value, inner_schema) do
        {:ok, root} -> {:cont, {:ok, acc_roots <> root}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp exported?(module, function, arity) do
    Code.ensure_loaded!(module)
    function_exported?(module, function, arity)
  end
end
