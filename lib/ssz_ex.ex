defmodule LambdaEthereumConsensus.SszEx do
  @moduledoc """
    SSZ library in Elixir
  """
  #################
  ### Public API
  #################
  def encode(value, {:int, size}), do: encode_int(value, size)
  def encode(value, :bool), do: encode_bool(value)

  def encode(list, {:list, basic_type, size}) do
    if variable_size?(basic_type),
      do: encode_variable_size_list(list, basic_type, size),
      else: encode_fixed_size_list(list, basic_type, size)
  end

  def encode(value, {:bytes, _}), do: {:ok, value}

  def encode(container, module) when is_map(container),
    do: encode_container(container, module.schema())

  def decode(binary, :bool), do: decode_bool(binary)
  def decode(binary, {:int, size}), do: decode_uint(binary, size)

  def decode(binary, {:list, basic_type, size}) do
    if variable_size?(basic_type),
      do: decode_variable_list(binary, basic_type, size),
      else: decode_list(binary, basic_type, size)
  end

  #################
  ### Private functions
  #################
  @bytes_per_length_offset 4
  @bits_per_byte 8

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
    values =
      schemas
      |> Enum.map(fn {key, schema} ->
        value = Map.get(container, key)
        {value, schema}
      end)

    with {:ok,
          {encoded_variable_parts, encoded_fixed_parts, variable_size_list,
           total_variable_byte_size, total_fixed_byte_size}} <- encode_container_parts(values),
         :ok <- check_length(total_fixed_byte_size, total_variable_byte_size),
         {variable_offsets, _} =
           Enum.reduce(variable_size_list, {[], 0}, fn element, {res, acc} ->
             sum = total_fixed_byte_size + acc
             {[sum | res], element + acc}
           end),
         {:ok, encoded_variable_offsets} <-
           variable_offsets
           |> Enum.reverse()
           |> Enum.map(&encode(&1, {:int, 32}))
           |> flatten_results() do
      {encoded_parts, _} =
        Enum.reduce(encoded_fixed_parts, {[], encoded_variable_offsets}, fn element,
                                                                            {acc_encoded_list,
                                                                             acc_offsets_list} ->
          if element == nil do
            [offset | rest_offsets] = acc_offsets_list
            {[offset | acc_encoded_list], rest_offsets}
          else
            {[element | acc_encoded_list], acc_offsets_list}
          end
        end)

      (Enum.reverse(encoded_parts) ++ encoded_variable_parts)
      |> :binary.list_to_bin()
      |> then(&{:ok, &1})
    end
  end

  defp encode_container_parts(values) do
    with {:ok,
          {encoded_variable_list, encoded_fixed_list, variable_size_list,
           total_variable_byte_size,
           total_fixed_byte_size}} <-
           Enum.reduce_while(values, {:ok, {[], [], [], 0, 0}}, fn {value, schema},
                                                                   {:ok,
                                                                    {res_encoded_variable_list,
                                                                     res_encoded_fixed_list,
                                                                     res_variable_size_list,
                                                                     varible_size_acc,
                                                                     fixed_size_acc}} ->
             encode_container_part(
               value,
               schema,
               res_encoded_variable_list,
               res_encoded_fixed_list,
               res_variable_size_list,
               varible_size_acc,
               fixed_size_acc
             )
           end) do
      {:ok,
       {Enum.reverse(encoded_variable_list), Enum.reverse(encoded_fixed_list),
        Enum.reverse(variable_size_list), total_variable_byte_size, total_fixed_byte_size}}
    end
  end

  defp encode_container_part(
         value,
         schema,
         res_encoded_variable_list,
         res_encoded_fixed_list,
         res_variable_size_list,
         varible_size_acc,
         fixed_size_acc
       ) do
    if variable_size?(schema) do
      case encode(value, schema) do
        {:ok, encoded} ->
          size = byte_size(encoded)

          {:cont,
           {:ok,
            {[encoded | res_encoded_variable_list], [nil | res_encoded_fixed_list],
             [size | res_variable_size_list], size + varible_size_acc,
             @bytes_per_length_offset + fixed_size_acc}}}

        error ->
          {:halt, {:error, error}}
      end
    else
      case encode(value, schema) do
        {:ok, encoded} ->
          size = byte_size(encoded)

          {:cont,
           {:ok,
            {res_encoded_variable_list, [encoded | res_encoded_fixed_list],
             res_variable_size_list, varible_size_acc, size + fixed_size_acc}}}

        error ->
          {:halt, {:error, error}}
      end
    end
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

  defp variable_size?({:list, _, _}), do: true
  defp variable_size?(:bool), do: false
  defp variable_size?({:int, _}), do: false
  defp variable_size?({:bytes, _}), do: false
end
