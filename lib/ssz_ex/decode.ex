defmodule SszEx.Decode do
  @moduledoc """
  The `Decode` module provides functions for decoding the SszEx schemas according to the Ethereum Simple Serialize (SSZ) specifications.
  """

  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Utils.BitVector
  alias SszEx.Error
  alias SszEx.Utils

  @bytes_per_length_offset 4
  @offset_bits 32

  @spec decode(binary(), SszEx.schema()) ::
          {:ok, any()} | {:error, Error.t()}
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
             do: decode_variable_container(binary, module) |> Utils.add_trace("#{module}"),
             else: decode_fixed_container(binary, module) |> Utils.add_trace("#{module}")
           ) do
      if exported?(module, :decode_ex, 1) do
        {:ok, module.decode_ex(result)}
      else
        {:ok, result}
      end
    end
  end

  defp decode_uint(binary, size) when bit_size(binary) != size,
    do:
      {:error,
       %Error{
         message:
           "Invalid binary length while decoding uint.\nExpected size: #{size}.\nFound:#{bit_size(binary)}\n"
       }}

  defp decode_uint(binary, size) do
    <<element::integer-size(size)-little, _rest::bitstring>> = binary
    {:ok, element}
  end

  defp decode_bool(binary) when byte_size(binary) != 1,
    do:
      {:error,
       %Error{
         message:
           "Invalid binary length while decoding bool.\nExpected size: 1.\nFound:#{byte_size(binary)}\n"
       }}

  defp decode_bool("\x01"), do: {:ok, true}
  defp decode_bool("\x00"), do: {:ok, false}

  defp decode_bool(binary),
    do:
      {:error,
       %Error{
         message:
           "Invalid binary value while decoding bool.\nExpected value: x01/x00.\nFound: x#{Base.encode16(binary)}."
       }}

  defp decode_bitlist("", _max_size),
    do:
      {:error,
       %Error{
         message: "Invalid binary value while decoding BitList.\nEmpty binary found.\n"
       }}

  defp decode_bitlist(bit_list, max_size) do
    num_bytes = byte_size(bit_list)
    decoded = BitList.new(bit_list)
    len = BitList.length(decoded)

    cond do
      match?(<<_::binary-size(num_bytes - 1), 0>>, bit_list) ->
        {:error,
         %Error{
           message: "Invalid binary value while decoding BitList.\nMissing sentinel bit.\n"
         }}

      len > max_size ->
        {:error,
         %Error{
           message:
             "Invalid binary length while decoding BitList. \nExpected max_size: #{max_size}. Found: #{len}.\n"
         }}

      true ->
        {:ok, decoded}
    end
  end

  defp decode_bitvector(bit_vector, size) do
    first_num_bytes = get_first_bytes(size)
    padding_bits = rem(8 - rem(size, 8), 8)

    case bit_vector do
      <<_first::binary-size(first_num_bytes), 0::size(padding_bits),
        _rest::size(8 - padding_bits)>> ->
        {:ok, BitVector.new(bit_vector, size)}

      _ ->
        {:error,
         %Error{
           message: "Invalid binary length while decoding BitVector. \nExpected size: #{size}.\n"
         }}
    end
  end

  defp get_first_bytes(size) when rem(size, 8) == 0, do: div(size, 8) - 1
  defp get_first_bytes(size), do: div(size, 8)

  defp decode_fixed_list(binary, inner_type, size) do
    fixed_size = Utils.get_fixed_size(inner_type)
    byte_length = byte_size(binary)

    with :ok <- check_valid_fixed_list_size(byte_length, inner_type, fixed_size, size),
         {:ok, _decoded_list} = result <-
           decode_fixed_collection(binary, fixed_size, inner_type) do
      result
    end
  end

  defp decode_fixed_vector(binary, inner_type, size) do
    fixed_size = Utils.get_fixed_size(inner_type)
    byte_size = byte_size(binary)

    with :ok <- check_valid_vector_size(byte_size, inner_type, fixed_size, size),
         {:ok, decoded_vector} = result <-
           decode_fixed_collection(binary, fixed_size, inner_type),
         :ok <- check_valid_vector_size_after_decode(size, length(decoded_vector)) do
      result
    end
  end

  defp check_valid_fixed_list_size(byte_length, inner_type, inner_type_size, max_size)
       when byte_length > inner_type_size * max_size,
       do:
         {:error,
          %Error{
            message:
              "Invalid binary length while decoding list of #{inspect(inner_type)}.\nExpected max_size: #{max_size}.\nFound: #{byte_length}\n"
          }}

  defp check_valid_fixed_list_size(_byte_length, _inner_type, _inner_type_size, _max_size),
    do: :ok

  defp check_valid_vector_size(byte_length, inner_type, inner_type_size, size)
       when byte_length != inner_type_size * size,
       do:
         {:error,
          %Error{
            message:
              "Invalid binary length while decoding vector of #{inspect(inner_type)}.\nExpected size #{inner_type_size * size} bytes.\nFound: #{byte_length}.\n"
          }}

  defp check_valid_vector_size(_byte_length, _inner_type, _inner_type_size, _size),
    do: :ok

  defp check_valid_vector_size_after_decode(size, decoded_size)
       when decoded_size == size and decoded_size > 0,
       do: :ok

  defp check_valid_vector_size_after_decode(size, decoded_size),
    do:
      {:error,
       %Error{
         message:
           "Invalid vector decoded size.\nExpected size: #{size}. Decoded vector size: #{decoded_size} "
       }}

  defp decode_variable_list("", _, _) do
    {:ok, []}
  end

  defp decode_variable_list(
         <<first_offset::integer-32-little, _rest_bytes::bitstring>>,
         inner_type,
         size
       )
       when div(first_offset, @bytes_per_length_offset) > size,
       do:
         {:error,
          %Error{
            message:
              "Invalid binary while decoding list of #{inspect(inner_type)}.\nExpected max_size: #{size}.\n First offset points to: #{first_offset}."
          }}

  defp decode_variable_list(binary, inner_type, _size) do
    <<first_offset::integer-32-little, rest_bytes::bitstring>> = binary
    num_elements = div(first_offset, @bytes_per_length_offset)

    if Integer.mod(first_offset, @bytes_per_length_offset) != 0 ||
         first_offset < @bytes_per_length_offset do
      {:error,
       %Error{
         message:
           "Invalid binary while decoding list of #{inspect(inner_type)}.\nFirst offset points to: #{first_offset}."
       }}
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

    with :ok <- check_fixed_container_size(module, fixed_length, byte_size),
         {:ok, fixed_parts, _offsets, _items_index} <-
           decode_fixed_section(binary, schemas, fixed_length) do
      {:ok, struct!(module, fixed_parts)}
    end
  end

  defp check_fixed_container_size(module, expected_length, size)
       when expected_length != size,
       do:
         {:error,
          %Error{
            message:
              "Invalid binary length while decoding #{module}. \nExpected #{expected_length}. \nFound #{size}.\n"
          }}

  defp check_fixed_container_size(_module, _expected_length, _size),
    do: :ok

  defp check_first_offset([{offset, _} | _rest], items_index, _binary_size)
       when offset != items_index,
       do:
         {:error,
          %Error{
            message:
              "First offset does not point to the first variable byte.\nExpected index: #{items_index}.\nOffset: #{offset}. "
          }}

  defp check_first_offset(_offsets, _items_index, _binary_size),
    do: :ok

  defp decode_variable_section(full_binary, binary, offsets) do
    offsets
    |> Enum.chunk_every(2, 1)
    |> Enum.reduce_while({binary, []}, fn
      [{offset, {key, schema}}, {next_offset, _}], {rest_bytes, acc_variable_parts} ->
        case sanitize_offset(next_offset, offset, byte_size(full_binary), nil) do
          :ok ->
            size = next_offset - offset
            <<chunk::binary-size(size), rest::bitstring>> = rest_bytes

            {:cont,
             {rest, [{key, decode(chunk, schema) |> Utils.add_trace(key)} | acc_variable_parts]}}

          error ->
            {:halt, {<<>>, [{key, error} | acc_variable_parts]}}
        end

      [{_offset, {key, schema}}], {rest_bytes, acc_variable_parts} ->
        {:cont,
         {<<>>, [{key, decode(rest_bytes, schema) |> Utils.add_trace(key)} | acc_variable_parts]}}
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

        {rest, [{key, decode(chunk, schema) |> Utils.add_trace(key)} | fixed_parts], offsets,
         items_index + ssz_fixed_len}
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
         %Error{
           message:
             "Offset points outside the binary. \nBinary length: #{num_bytes}.\nOffset: #{offset}"
         }}

      previous_offset != nil && previous_offset > offset ->
        {:error,
         %Error{
           message:
             "Offset points to bytes prior to the previous offset.\nPrevious offset: #{previous_offset}.\nOffset: #{offset}"
         }}

      true ->
        :ok
    end
  end

  defp sanitize_offset(offset, previous_offset, _num_bytes, num_fixed_bytes) do
    cond do
      offset < num_fixed_bytes ->
        {:error,
         %Error{
           message:
             "Offset points “backwards” into the fixed-bytes portion. \nFirst variable byte index: #{num_fixed_bytes}.\nOffset: #{offset}."
         }}

      previous_offset == nil && offset != num_fixed_bytes ->
        {:error,
         %Error{
           message:
             "Offset does not point to the first variable byte.\nExpected index: #{num_fixed_bytes}.\nOffset: #{offset}."
         }}

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
          %Error{
            message:
              "Invalid binary length while decoding collection. \nInner type size: #{chunk_size} bytes. Binary length: #{byte_size(binary)} bytes.\n"
          }}
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
      %{error: [first_error | _rest]} -> {:error, first_error}
      summary -> {:ok, Map.get(summary, :ok, [])}
    end
  end

  defp exported?(module, function, arity) do
    Code.ensure_loaded!(module)
    function_exported?(module, function, arity)
  end
end
