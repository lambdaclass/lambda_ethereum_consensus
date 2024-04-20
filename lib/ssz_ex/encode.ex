defmodule SszEx.Encode do
  @moduledoc """
   The `Encode` module provides functions for encoding the SszEx schemas according to the Ethereum Simple Serialize (SSZ) specifications.
  """

  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Utils.BitVector
  alias SszEx.Error
  alias SszEx.Utils

  import BitVector

  @bytes_per_length_offset 4
  @bits_per_byte 8

  @spec encode(any(), SszEx.schema()) ::
          {:ok, binary()} | {:error, Error.t()}
  def encode(value, {:int, size}), do: encode_int(value, size)
  def encode(value, :bool), do: encode_bool(value)
  def encode(value, {:byte_list, _}), do: {:ok, value}
  def encode(value, {:byte_vector, _}), do: {:ok, value}

  def encode(list, {:list, inner_type, size}) do
    if Utils.variable_size?(inner_type),
      do: encode_variable_size_list(list, inner_type, size),
      else: encode_fixed_size_list(list, inner_type, size)
  end

  def encode(vector, {:vector, inner_type, size}) do
    if Utils.variable_size?(inner_type),
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

  defp encode_int(value, size) when is_integer(value), do: {:ok, <<value::size(size)-little>>}
  defp encode_bool(true), do: {:ok, "\x01"}
  defp encode_bool(false), do: {:ok, "\x00"}

  defp encode_fixed_size_list(list, inner_type, max_size) do
    size = Enum.count(list)

    if size > max_size do
      {:error,
       %Error{
         message:
           "Invalid binary length while encoding list of #{inspect(inner_type)}.\nExpected max_size: #{max_size}.\nFound: #{size}\n"
       }}
    else
      list
      |> Enum.map(&encode(&1, inner_type))
      |> Utils.flatten_results_by(&Enum.join/1)
    end
  end

  defp encode_bitlist(bit_list, max_size) do
    len = bit_size(bit_list)

    if len > max_size do
      {:error,
       %Error{
         message:
           "Invalid binary length while encoding BitList.\nExpected max_size: #{max_size}. Found: #{len}.\n"
       }}
    else
      {:ok, BitList.to_bytes(bit_list)}
    end
  end

  defp encode_bitvector(bit_vector, size) when bit_vector_size(bit_vector) != size,
    do:
      {:error,
       %Error{
         message:
           "Invalid binary length while encoding BitVector. \nExpected: #{size}.\nFound: #{bit_vector_size(bit_vector)}."
       }}

  defp encode_bitvector(bit_vector, _size),
    do: {:ok, BitVector.to_bytes(bit_vector)}

  defp encode_variable_size_list(list, inner_type, max_size) do
    size = Enum.count(list)

    if size > max_size do
      {:error,
       %Error{
         message:
           "Invalid binary length while encoding list of #{inspect(inner_type)}.\nExpected max_size: #{max_size}.\nFound: #{size}\n"
       }}
    else
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
             |> Utils.flatten_results() do
        (encoded_variable_offsets ++ encoded_variable_parts)
        |> :binary.list_to_bin()
        |> then(&{:ok, &1})
      end
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

               {:error, %Error{}} = error ->
                 {:halt, error}
             end
           end) do
      {:ok, {Enum.reverse(encoded_list), Enum.reverse(byte_size_list), total_byte_size}}
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

      if Utils.variable_size?(schema) do
        {[:offset | acc_fixed_size_values], @bytes_per_length_offset + acc_fixed_length,
         [{value, schema} | acc_variable_values]}
      else
        {[{value, schema} | acc_fixed_size_values],
         acc_fixed_length + Utils.get_fixed_size(schema), acc_variable_values}
      end
    end)
  end

  defp encode_schemas(tuple_values) do
    Enum.map(tuple_values, fn {value, schema} -> encode(value, schema) end)
    |> Utils.flatten_results()
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

  defp check_length(fixed_lengths, total_byte_size) do
    if fixed_lengths + total_byte_size <
         2 ** (@bytes_per_length_offset * @bits_per_byte) do
      :ok
    else
      {:error,
       %Error{
         message:
           "Invalid binary size after encoding. Size out of offset range. Size: #{fixed_lengths + total_byte_size}"
       }}
    end
  end
end
