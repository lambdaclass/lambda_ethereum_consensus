defmodule LambdaEthereumConsensus.SszEx do
  @moduledoc """
    SSZ library in Elixir
  """
  alias LambdaEthereumConsensus.Utils.BitVector
  import alias LambdaEthereumConsensus.Utils.BitVector

  #################
  ### Public API
  #################
  import Bitwise

  @bytes_per_chunk 32
  @bits_per_byte 8
  @bits_per_chunk @bytes_per_chunk * @bits_per_byte
  @zero_chunk <<0::size(@bits_per_chunk)>>

  @spec hash(iodata()) :: binary()
  def hash(data), do: :crypto.hash(:sha256, data)

  @spec hash_nodes(binary(), binary()) :: binary()
  def hash_nodes(left, right), do: :crypto.hash(:sha256, left <> right)

  def encode(value, {:int, size}), do: encode_int(value, size)
  def encode(value, :bool), do: encode_bool(value)
  def encode(value, {:bytes, _}), do: {:ok, value}

  def encode(list, {:list, basic_type, size}) do
    if variable_size?(basic_type),
      do: encode_variable_size_list(list, basic_type, size),
      else: encode_fixed_size_list(list, basic_type, size)
  end

  def encode(vector, {:vector, basic_type, size}),
    do: encode_fixed_size_list(vector, basic_type, size)

  def encode(value, {:bitlist, max_size}) when is_bitstring(value),
    do: encode_bitlist(value, max_size)

  def encode(value, {:bitlist, max_size}) when is_integer(value),
    do: encode_bitlist(:binary.encode_unsigned(value), max_size)

  def encode(value, {:bitvector, size}) when is_bitvector(value),
    do: encode_bitvector(value, size)

  def encode(container, module) when is_map(container),
    do: encode_container(container, module.schema())

  def decode(binary, :bool), do: decode_bool(binary)
  def decode(binary, {:int, size}), do: decode_uint(binary, size)
  def decode(value, {:bytes, _}), do: {:ok, value}

  def decode(binary, {:list, basic_type, size}) do
    if variable_size?(basic_type),
      do: decode_variable_list(binary, basic_type, size),
      else: decode_list(binary, basic_type, size)
  end

  def decode(binary, {:vector, basic_type, size}), do: decode_list(binary, basic_type, size)

  def decode(value, {:bitlist, max_size}) when is_bitstring(value),
    do: decode_bitlist(value, max_size)

  def decode(value, {:bitvector, size}) when is_bitstring(value),
    do: decode_bitvector(value, size)

  def decode(binary, module) when is_atom(module), do: decode_container(binary, module)

  @spec hash_tree_root!(boolean, atom) :: Types.root()
  def hash_tree_root!(value, :bool), do: pack(value, :bool)

  @spec hash_tree_root!(non_neg_integer, {:int, non_neg_integer}) :: Types.root()
  def hash_tree_root!(value, {:int, size}), do: pack(value, {:int, size})

  @spec hash_tree_root(list(), {:list, any, non_neg_integer}) ::
          {:ok, Types.root()} | {:error, String.t()}
  def hash_tree_root(list, {:list, type, size}) do
    if variable_size?(type) do
      # TODO
      # hash_tree_root_list_complex_type(list, {:list, type, size}, limit)
      {:error, "Not implemented"}
    else
      packed_chunks = pack(list, {:list, type, size})
      limit = chunk_count({:list, type, size})
      len = length(list)
      hash_tree_root_list_basic_type(packed_chunks, limit, len)
    end
  end

  @spec hash_tree_root_list_basic_type(binary(), non_neg_integer, non_neg_integer) ::
          {:ok, Types.root()} | {:error, String.t()}
  def hash_tree_root_list_basic_type(chunks, limit, len) do
    chunks_len = chunks |> byte_size() |> div(@bytes_per_chunk)

    if chunks_len > limit do
      {:error, "chunk size exceeds limit"}
    else
      root = merkleize_chunks(chunks, limit) |> mix_in_length(len)
      {:ok, root}
    end
  end

  @spec mix_in_length(Types.root(), non_neg_integer) :: Types.root()
  def mix_in_length(root, len) do
    {:ok, serialized_len} = encode_int(len, @bits_per_chunk)
    root |> hash_nodes(serialized_len)
  end

  def merkleize_chunks(chunks, leaf_count \\ nil) do
    chunks_len = chunks |> byte_size() |> div(@bytes_per_chunk)

    if chunks_len == 1 and leaf_count == nil do
      chunks
    else
      node_count = 2 * leaf_count - 1
      interior_count = node_count - leaf_count
      leaf_start = interior_count * @bytes_per_chunk
      padded_chunks = chunks |> convert_to_next_pow_of_two(leaf_count)
      buffer = <<0::size(leaf_start * @bits_per_byte), padded_chunks::bitstring>>

      new_buffer =
        1..node_count
        |> Enum.filter(fn x -> rem(x, 2) == 0 end)
        |> Enum.reverse()
        |> Enum.reduce(buffer, fn index, acc_buffer ->
          parent_index = (index - 1) |> div(2)
          start = parent_index * @bytes_per_chunk
          stop = (index + 1) * @bytes_per_chunk
          focus = acc_buffer |> :binary.part(start, stop - start)
          focus_len = focus |> byte_size()
          children_index = focus_len - 2 * @bytes_per_chunk
          children = focus |> :binary.part(children_index, focus_len - children_index)

          <<left::binary-size(@bytes_per_chunk), right::binary-size(@bytes_per_chunk)>> = children

          parent = hash_nodes(left, right)
          replace_chunk(acc_buffer, start, parent)
        end)

      <<root::binary-size(@bytes_per_chunk), _::binary>> = new_buffer
      root
    end
  end

  def merkleize_chunks_with_virtual_padding(chunks, leaf_count \\ nil) do
    <<>>
  end

  @spec pack(boolean, :bool) :: binary()
  def pack(true, :bool), do: <<1::@bits_per_chunk-little>>
  def pack(false, :bool), do: @zero_chunk

  @spec pack(non_neg_integer, {:int, non_neg_integer}) :: binary()
  def pack(value, {:int, size}) do
    <<value::size(size)-little>> |> pack_bytes()
  end

  @spec pack(list(), {:list, any, non_neg_integer}) :: binary() | :error
  def pack(list, {:list, schema, _size}) do
    if variable_size?(schema) do
      # TODO
      # pack_complex_type_list(list)
      :error
    else
      pack_basic_type_list(list, schema)
    end
  end

  def chunk_count({:list, {:int, size}, max_size}) do
    size = size_of({:int, size})
    (max_size * size + 31) |> div(32)
  end

  def chunk_count({:list, :bool, max_size}) do
    size = size_of(:bool)
    (max_size * size + 31) |> div(32)
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

  defp decode_uint(binary, size) do
    <<element::integer-size(size)-little, _rest::bitstring>> = binary
    {:ok, element}
  end

  defp decode_bool("\x01"), do: {:ok, true}
  defp decode_bool("\x00"), do: {:ok, false}

  defp encode_fixed_size_list(list, _basic_type, max_size) when length(list) > max_size,
    do: {:error, "invalid max_size of list"}

  defp encode_fixed_size_list(list, basic_type, _size) when is_list(list) do
    list
    |> Enum.map(&encode(&1, basic_type))
    |> flatten_results_by(&Enum.join/1)
  end

  defp encode_bitlist(bit_list, max_size) do
    len = bit_size(bit_list)

    if len > max_size do
      {:error, "excess bits"}
    else
      r = rem(len, @bits_per_byte)
      <<pre::bitstring-size(len - r), post::bitstring-size(r)>> = bit_list
      {:ok, <<pre::bitstring, 1::size(@bits_per_byte - r), post::bitstring>>}
    end
  end

  defp encode_bitvector(bit_vector, size) when bit_vector_size(bit_vector) == size,
    do: {:ok, BitVector.to_bytes(bit_vector)}

  defp encode_bitvector(_bit_vector, _size), do: {:error, "invalid bit_vector length"}

  defp encode_variable_size_list(list, _basic_type, max_size) when length(list) > max_size,
    do: {:error, "invalid max_size of list"}

  defp encode_variable_size_list(list, basic_type, _size) when is_list(list) do
    fixed_lengths = @bytes_per_length_offset * length(list)

    with {:ok, {encoded_variable_parts, variable_offsets_list, total_byte_size}} <-
           encode_variable_parts(list, basic_type),
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

  defp encode_variable_parts(list, basic_type) do
    with {:ok, {encoded_list, byte_size_list, total_byte_size}} <-
           Enum.reduce_while(list, {:ok, {[], [], 0}}, fn value,
                                                          {:ok, {res_encoded, res_size, acc}} ->
             case encode(value, basic_type) do
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

  defp decode_bitlist(bit_list, max_size) do
    num_bytes = byte_size(bit_list)
    num_bits = bit_size(bit_list)
    len = length_of_bitlist(bit_list)
    <<pre::size(num_bits - 8), last_byte::8>> = bit_list
    decoded = <<pre::size(num_bits - 8), remove_trailing_bit(<<last_byte>>)::bitstring>>

    cond do
      len < 0 ->
        {:error, "missing length information"}

      div(len, @bits_per_byte) + 1 != num_bytes ->
        {:error, "invalid byte count"}

      len > max_size ->
        {:error, "out of bounds"}

      true ->
        {:ok, decoded}
    end
  end

  defp decode_bitvector(bit_vector, size) when bit_size(bit_vector) == size,
    do: {:ok, BitVector.new(bit_vector, size)}

  defp decode_bitvector(_bit_vector, _size), do: {:error, "invalid bit_vector length"}

  defp decode_list(binary, basic_type, size) do
    fixed_size = get_fixed_size(basic_type)

    with {:ok, decoded_list} = result <-
           binary
           |> decode_chunk(fixed_size, basic_type)
           |> flatten_results() do
      if length(decoded_list) > size do
        {:error, "invalid max_size of list"}
      else
        result
      end
    end
  end

  defp decode_variable_list(binary, _, _) when byte_size(binary) == 0 do
    {:ok, []}
  end

  defp decode_variable_list(
         <<first_offset::integer-32-little, _rest_bytes::bitstring>>,
         _basic_type,
         size
       )
       when div(first_offset, @bytes_per_length_offset) > size,
       do: {:error, "invalid length list"}

  defp decode_variable_list(binary, basic_type, _size) do
    <<first_offset::integer-32-little, rest_bytes::bitstring>> = binary
    num_elements = div(first_offset, @bytes_per_length_offset)

    if Integer.mod(first_offset, @bytes_per_length_offset) != 0 ||
         first_offset < @bytes_per_length_offset do
      {:error, "InvalidListFixedBytesLen"}
    else
      with {:ok, first_offset} <-
             sanitize_offset(first_offset, nil, byte_size(binary), first_offset) do
        decode_variable_list_elements(
          num_elements,
          rest_bytes,
          basic_type,
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
         basic_type,
         offset,
         binary,
         _first_offset,
         results
       ) do
    part = :binary.part(binary, offset, byte_size(binary) - offset)
    [decode(part, basic_type) | results]
  end

  defp decode_variable_list_elements(
         num_elements,
         acc_rest_bytes,
         basic_type,
         offset,
         binary,
         first_offset,
         results
       ) do
    <<next_offset::integer-32-little, rest_bytes::bitstring>> = acc_rest_bytes

    with {:ok, next_offset} <-
           sanitize_offset(next_offset, offset, byte_size(binary), first_offset) do
      part = :binary.part(binary, offset, next_offset - offset)

      decode_variable_list_elements(
        num_elements - 1,
        rest_bytes,
        basic_type,
        next_offset,
        binary,
        first_offset,
        [decode(part, basic_type) | results]
      )
    end
  end

  defp encode_container(container, schemas) do
    {fixed_size_values, fixed_length, variable_values} = analyze_schemas(container, schemas)

    with {:ok, variable_parts} <- encode_schemas(variable_values),
         offsets = calculate_offsets(variable_parts, fixed_length),
         variable_length =
           Enum.reduce(variable_parts, 0, fn part, acc -> byte_size(part) + acc end),
         :ok <- check_length(fixed_length, variable_length),
         {:ok, fixed_parts} <-
           replace_offsets(fixed_size_values, offsets)
           |> encode_schemas do
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

  defp decode_container(binary, module) do
    schemas = module.schema()
    fixed_length = get_fixed_length(schemas)
    <<fixed_binary::binary-size(fixed_length), variable_binary::bitstring>> = binary

    with {:ok, fixed_parts, offsets} <- decode_fixed_section(fixed_binary, schemas, fixed_length),
         {:ok, variable_parts} <- decode_variable_section(variable_binary, offsets) do
      {:ok, struct!(module, fixed_parts ++ variable_parts)}
    end
  end

  defp decode_variable_section(binary, offsets) do
    offsets
    |> Enum.chunk_every(2, 1)
    |> Enum.reduce({binary, []}, fn
      [{offset, {key, schema}}, {next_offset, _}], {rest_bytes, acc_variable_parts} ->
        size = next_offset - offset
        <<chunk::binary-size(size), rest::bitstring>> = rest_bytes
        {rest, [{key, decode(chunk, schema)} | acc_variable_parts]}

      [{_offset, {key, schema}}], {rest_bytes, acc_variable_parts} ->
        {<<>>, [{key, decode(rest_bytes, schema)} | acc_variable_parts]}
    end)
    |> then(fn {<<>>, variable_parts} ->
      flatten_container_results(variable_parts)
    end)
  end

  defp decode_fixed_section(binary, schemas, fixed_length) do
    schemas
    |> Enum.reduce({binary, [], []}, fn {key, schema}, {binary, fixed_parts, offsets} ->
      if variable_size?(schema) do
        <<offset::integer-size(@offset_bits)-little, rest::bitstring>> = binary
        {rest, fixed_parts, [{offset - fixed_length, {key, schema}} | offsets]}
      else
        ssz_fixed_len = get_fixed_size(schema)
        <<chunk::binary-size(ssz_fixed_len), rest::bitstring>> = binary
        {rest, [{key, decode(chunk, schema)} | fixed_parts], offsets}
      end
    end)
    |> then(fn {_rest_bytes, fixed_parts, offsets} ->
      Tuple.append(flatten_container_results(fixed_parts), Enum.reverse(offsets))
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
  defp sanitize_offset(offset, previous_offset, num_bytes, num_fixed_bytes) do
    cond do
      offset < num_fixed_bytes ->
        {:error, "OffsetIntoFixedPortion"}

      previous_offset == nil && offset != num_fixed_bytes ->
        {:error, "OffsetSkipsVariableBytes"}

      offset > num_bytes ->
        {:error, "OffsetOutOfBounds"}

      previous_offset != nil && previous_offset > offset ->
        {:error, "OffsetsAreDecreasing"}

      true ->
        {:ok, offset}
    end
  end

  defp decode_chunk(binary, chunk_size, basic_type) do
    decode_chunk(binary, chunk_size, basic_type, [])
    |> Enum.reverse()
  end

  defp decode_chunk(<<>>, _chunk_size, _basic_type, results), do: results

  defp decode_chunk(binary, chunk_size, basic_type, results) do
    <<element::binary-size(chunk_size), rest::bitstring>> = binary
    decode_chunk(rest, chunk_size, basic_type, [decode(element, basic_type) | results])
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
  defp get_fixed_size({:bytes, size}), do: size

  defp get_fixed_size(module) when is_atom(module) do
    schemas = module.schema()

    schemas
    |> Enum.map(fn {_, schema} -> get_fixed_size(schema) end)
    |> Enum.sum()
  end

  defp variable_size?({:list, _, _}), do: true
  defp variable_size?(:bool), do: false
  defp variable_size?({:int, _}), do: false
  defp variable_size?({:bytes, _}), do: false

  defp variable_size?(module) when is_atom(module) do
    module.schema()
    |> Enum.map(fn {_, schema} -> variable_size?(schema) end)
    |> Enum.any?()
  end

  def length_of_bitlist(bitlist) when is_binary(bitlist) do
    bit_size = bit_size(bitlist)
    <<_::size(bit_size - 8), last_byte>> = bitlist
    bit_size - leading_zeros(<<last_byte>>) - 1
  end

  defp leading_zeros(<<1::1, _::7>>), do: 0
  defp leading_zeros(<<0::1, 1::1, _::6>>), do: 1
  defp leading_zeros(<<0::2, 1::1, _::5>>), do: 2
  defp leading_zeros(<<0::3, 1::1, _::4>>), do: 3
  defp leading_zeros(<<0::4, 1::1, _::3>>), do: 4
  defp leading_zeros(<<0::5, 1::1, _::2>>), do: 5
  defp leading_zeros(<<0::6, 1::1, _::1>>), do: 6
  defp leading_zeros(<<0::7, 1::1>>), do: 7
  defp leading_zeros(<<0::8>>), do: 8

  @spec remove_trailing_bit(binary()) :: bitstring()
  defp remove_trailing_bit(<<1::1, rest::7>>), do: <<rest::7>>
  defp remove_trailing_bit(<<0::1, 1::1, rest::6>>), do: <<rest::6>>
  defp remove_trailing_bit(<<0::2, 1::1, rest::5>>), do: <<rest::5>>
  defp remove_trailing_bit(<<0::3, 1::1, rest::4>>), do: <<rest::4>>
  defp remove_trailing_bit(<<0::4, 1::1, rest::3>>), do: <<rest::3>>
  defp remove_trailing_bit(<<0::5, 1::1, rest::2>>), do: <<rest::2>>
  defp remove_trailing_bit(<<0::6, 1::1, rest::1>>), do: <<rest::1>>
  defp remove_trailing_bit(<<0::7, 1::1>>), do: <<0::0>>
  defp remove_trailing_bit(<<0::8>>), do: <<0::0>>

  defp size_of(:bool), do: @bytes_per_boolean

  defp size_of({:int, size}), do: size |> div(@bits_per_byte)

  defp pack_basic_type_list(list, schema) do
    list
    |> Enum.reduce(<<>>, fn x, acc ->
      {:ok, encoded} = encode(x, schema)
      acc <> encoded
    end)
    |> pack_bytes()
  end

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

  defp next_pow_of_two(len) when is_integer(len) and len >= 0 do
    if len == 0 do
      0
    else
      n = ((len <<< 1) - 1) |> :math.log2() |> trunc()
      2 ** n
    end
  end

  defp replace_chunk(chunks, start, new_chunk) do
    <<left::binary-size(start), _::size(@bits_per_chunk), right::binary>> =
      chunks

    <<left::binary, new_chunk::binary, right::binary>>
  end
end
