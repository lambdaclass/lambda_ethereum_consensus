defmodule LambdaEthereumConsensus.SszEx.Decode do
  @moduledoc """
  Decode
  """

  alias LambdaEthereumConsensus.SszEx.Utils
  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Utils.BitVector

  import Bitwise
  @bits_per_byte 8
  @bytes_per_length_offset 4
  @offset_bits 32

  @spec decode(binary(), LambdaEthereumConsensus.SszEx.schema()) ::
          {:ok, any()} | {:error, String.t()}
  def decode(binary, :bool), do: decode_bool(binary)
  def decode(binary, {:int, size}), do: decode_uint(binary, size)
  def decode(value, {:byte_list, _}), do: {:ok, value}
  def decode(value, {:byte_vector, _}), do: {:ok, value}

  def decode(binary, {:list, inner_type, size}) do
    if Utils.variable_size?(inner_type),
      do: decode_variable_list(binary, inner_type, size),
      else: decode_fixed_list(binary, inner_type, size)
  end

  def decode(binary, {:vector, inner_type, size}) do
    if Utils.variable_size?(inner_type),
      do: decode_variable_list(binary, inner_type, size),
      else: decode_fixed_vector(binary, inner_type, size)
  end

  def decode(value, {:bitlist, max_size}) when is_bitstring(value),
    do: decode_bitlist(value, max_size)

  def decode(value, {:bitvector, size}) when is_bitstring(value),
    do: decode_bitvector(value, size)

  def decode(binary, module) when is_atom(module) do
    with {:ok, result} <-
           if(Utils.variable_size?(module),
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

  defp decode_uint(binary, size) when bit_size(binary) == size do
    <<element::integer-size(size)-little, _rest::bitstring>> = binary
    {:ok, element}
  end

  defp decode_uint(_binary, size), do: {:error, "invalid byte size #{inspect(size)}"}

  defp decode_bool("\x01"), do: {:ok, true}
  defp decode_bool("\x00"), do: {:ok, false}
  defp decode_bool(_), do: {:error, "invalid bool value"}

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
    fixed_size = Utils.get_fixed_size(inner_type)

    with {:ok, decoded_list} = result <- decode_fixed_collection(binary, fixed_size, inner_type),
         :ok <- check_valid_list_size_after_decode(size, length(decoded_list)) do
      result
    end
  end

  defp decode_fixed_vector(binary, inner_type, size) do
    fixed_size = Utils.get_fixed_size(inner_type)

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
        |> Utils.flatten_results()
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
      if Utils.variable_size?(schema) do
        <<offset::integer-size(@offset_bits)-little, rest::bitstring>> = binary

        {rest, fixed_parts, [{offset, {key, schema}} | offsets],
         items_index + @bytes_per_length_offset}
      else
        ssz_fixed_len = Utils.get_fixed_size(schema)
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
      if Utils.variable_size?(schema) do
        @bytes_per_length_offset
      else
        Utils.get_fixed_size(schema)
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
    |> Utils.flatten_results()
  end

  defp decode_fixed_collection(<<>>, _chunk_size, _inner_type, results), do: results

  defp decode_fixed_collection(binary, chunk_size, _inner_type, results)
       when byte_size(binary) < chunk_size,
       do: [{:error, "InvalidByteLength"} | results]

  defp decode_fixed_collection(binary, chunk_size, inner_type, results) do
    <<element::binary-size(chunk_size), rest::bitstring>> = binary
    decode_fixed_collection(rest, chunk_size, inner_type, [decode(element, inner_type) | results])
  end

  defp flatten_container_results(results) do
    case Enum.group_by(results, fn {_, {type, _}} -> type end, fn {key, {_, result}} ->
           {key, result}
         end) do
      %{error: errors} -> {:error, errors}
      summary -> {:ok, Map.get(summary, :ok, [])}
    end
  end

  defp exported?(module, function, arity) do
    Code.ensure_loaded!(module)
    function_exported?(module, function, arity)
  end
end
