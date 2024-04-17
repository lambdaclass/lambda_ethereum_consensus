defmodule SszEx.Decode do
  @moduledoc """
  The `Decode` module provides functions for decoding the SszEx schemas according to the Ethereum Simple Serialize (SSZ) specifications.
  """

  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Utils.BitVector
  alias SszEx.Utils

  import Bitwise
  @bytes_per_length_offset 4
  @offset_bits 32

  @spec decode(binary(), SszEx.schema()) ::
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

  defp decode_uint(binary, size),
    do:
      {:error,
       "Invalid binary length when decoding uint.\nExpected size: #{size}.\nFound:#{bit_size(binary)}\nBinary:#{inspect(binary)}"}

  defp decode_bool("\x01"), do: {:ok, true}
  defp decode_bool("\x00"), do: {:ok, false}

  defp decode_bool(binary),
    do:
      {:error,
       "Invalid binary value when decoding bool.\nExpected value: x01/x00.\nFound: x#{Base.encode16(binary)}."}

  defp decode_bitlist(bit_list, max_size) when bit_size(bit_list) > 0 do
    num_bytes = byte_size(bit_list)
    decoded = BitList.new(bit_list)
    len = BitList.length(decoded)

    cond do
      match?(<<_::binary-size(num_bytes - 1), 0>>, bit_list) ->
        {:error,
         "Invalid binary value when decoding BitList.\nBinary has no length information.\nBinary: #{inspect(bit_list)}."}

      len > max_size ->
        {:error,
         "Invalid binary length when decoding BitList. \nExpected max_size: #{max_size}. Found: #{len}.\nBinary: #{inspect(bit_list)}"}

      true ->
        {:ok, decoded}
    end
  end

  defp decode_bitlist(_binary, _max_size),
    do: {:error, "Invalid binary value when decoding BitList.\nEmpty binary found.\n"}

  defp decode_bitvector(bit_vector, size) do
    num_bytes = byte_size(bit_vector)

    cond do
      bit_size(bit_vector) == 0 ->
        {:error, "Invalid binary value when decoding BitVector.\nEmpty binary found.\n"}

      num_bytes != max(1, div(size + 7, 8)) ->
        {:error,
         "Invalid binary length when decoding BitVector. \nExpected size: #{size}.\nBinary: #{inspect(bit_vector)}"}

      true ->
        case bit_vector do
          # Padding bits are clear
          <<_first::binary-size(num_bytes - 1), 0::size(8 - rem(size, 8) &&& 7),
            _rest::bitstring>> ->
            {:ok, BitVector.new(bit_vector, size)}

          _else ->
            {:error,
             "Invalid binary length when decoding BitVector. \nExpected size: #{size}.\nBinary: #{inspect(bit_vector)}"}
        end
    end
  end

  defp decode_fixed_list(binary, inner_type, size) do
    fixed_size = Utils.get_fixed_size(inner_type)
    byte_length = byte_size(binary)

    if byte_length > fixed_size * size do
      {:error,
       "Invalid binary length when decoding list of #{inspect(inner_type)}.\nExpected max_size: #{size}.\nFound: #{byte_length}\nBinary: #{inspect(binary)}"}
    else
      with {:ok, _decoded_list} = result <-
             decode_fixed_collection(binary, fixed_size, inner_type) do
        result
      end
    end
  end

  defp decode_fixed_vector(binary, inner_type, size) do
    fixed_size = Utils.get_fixed_size(inner_type)
    byte_size = byte_size(binary)

    if fixed_size * size != byte_size do
      {:error,
       "Invalid binary length while decoding vector of #{inspect(inner_type)}.\nExpected size #{fixed_size * size}. Found: #{byte_size}.\nBinary: #{inspect(binary)}."}
    else
      with {:ok, _decoded_vector} = result <-
             decode_fixed_collection(binary, fixed_size, inner_type) do
        result
      end
    end
  end

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
    byte_size = byte_size(binary)

    if fixed_length != byte_size do
      {:error,
       "Invalid binary length while decoding #{module}. \nExpected #{fixed_length}. \nFound #{byte_size}.\n Binary: #{inspect(binary)}"}
    else
      with {:ok, fixed_parts, _offsets, _items_index} <-
             decode_fixed_section(binary, schemas, fixed_length) do
        {:ok, struct!(module, fixed_parts)}
      end
    end
  end

  defp check_first_offset([{offset, _} | _rest], items_index, _binary_size) do
    cond do
      offset < items_index ->
        {:error,
         "First offset points “backwards” into the fixed-bytes portion. \nExpected index: #{items_index}.\nOffset: #{offset}."}

      offset > items_index ->
        {:error,
         "First offset does not point to the first variable byte.\nExpected index: #{items_index}.\nOffset: #{offset}. "}

      true ->
        :ok
    end
  end

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
        {:error,
         "Offset points outside the binary. \nBinary length: #{num_bytes}.\nOffset: #{offset}"}

      previous_offset != nil && previous_offset > offset ->
        {:error,
         "Offset points to bytes prior to the previous offset.\nPrevious offset: #{previous_offset}.\nOffset: #{offset}"}

      true ->
        :ok
    end
  end

  defp sanitize_offset(offset, previous_offset, _num_bytes, num_fixed_bytes) do
    cond do
      offset < num_fixed_bytes ->
        {:error,
         "Offset points “backwards” into the fixed-bytes portion. \nFirst variable byte index: #{num_fixed_bytes}.\nOffset: #{offset}."}

      previous_offset == nil && offset != num_fixed_bytes ->
        {:error,
         "Offset does not point to the first variable byte.\nExpected index: #{num_fixed_bytes}.\nOffset: #{offset}."}

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
       do: [
         {:error,
          "Invalid binary length while decoding collection. \nInner type size: #{chunk_size}.\nBinary: #{inspect(binary)}."}
         | results
       ]

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
