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

  defp encode_fixed_size_list(list, basic_type, _size) when is_list(list) do
    list
    |> Enum.map(&encode(&1, basic_type))
    |> Enum.map(fn {:ok, result} -> result end)
    |> :binary.list_to_bin()
    |> then(&{:ok, &1})
  end

  defp encode_variable_size_list(list, basic_type, _size) when is_list(list) do
    fixed_lengths = List.duplicate(@bytes_per_length_offset, length(list))

    variable_parts =
      list
      |> Enum.map(&encode(&1, basic_type))
      |> Enum.map(fn {:ok, result} -> result end)

    variable_lengths =
      variable_parts
      |> Enum.map(&byte_size(&1))

    if Enum.sum(fixed_lengths ++ variable_lengths) <
         2 ** (@bytes_per_length_offset * @bits_per_byte) do
      variable_offsets =
        0..(length(list) - 1)
        |> Enum.map(fn i ->
          slice_variable_legths = Enum.take(variable_lengths, i)
          sum = Enum.sum(fixed_lengths ++ slice_variable_legths)
          {:ok, result} = encode(sum, {:int, 32})
          result
        end)

      (variable_offsets ++ variable_parts)
      |> :binary.list_to_bin()
      |> then(&{:ok, &1})
    else
      {:error, "invalid lengths"}
    end
  end

  defp decode_list(binary, basic_type, _size) do
    fixed_size = get_fixed_size(basic_type)

    :binary.bin_to_list(binary)
    |> Enum.chunk_every(fixed_size)
    |> Enum.map(&:binary.list_to_bin(&1))
    |> Enum.map(&decode(&1, basic_type))
    |> Enum.map(fn {:ok, result} -> result end)
    |> then(&{:ok, &1})
  end

  defp decode_variable_list(binary, basic_type, _size) do
    if byte_size(binary) == 0 do
      {:error, "Error trying to collect empty list"}
    else
      <<first_offset::integer-32-little, rest_bytes::bitstring>> = binary
      num_items = div(first_offset, @bytes_per_length_offset)

      if Integer.mod(first_offset, @bytes_per_length_offset) != 0 ||
           first_offset < @bytes_per_length_offset do
        {:error, "InvalidListFixedBytesLen"}
      else
        with {:ok, first_offset} <-
               sanitize_offset(first_offset, nil, byte_size(binary), first_offset) do
          {:ok, {decoded_list, _, _}} =
            decode_variable_list(first_offset, rest_bytes, num_items, binary, basic_type)

          {:ok, decoded_list |> Enum.reverse()}
        end
      end
    end
  end

  @spec decode_variable_list(integer(), binary, integer(), binary, any) ::
          {:ok, {list, integer(), binary}} | {:error, String.t()}
  defp decode_variable_list(first_offset, rest_bytes, num_items, binary, basic_type) do
    1..num_items
    |> Enum.reduce_while({:ok, {[], first_offset, rest_bytes}}, fn i,
                                                                   {:ok,
                                                                    {acc_decoded, offset,
                                                                     acc_rest_bytes}} ->
      if i == num_items do
        part = :binary.part(binary, offset, byte_size(binary) - offset)

        with {:ok, decoded} <- decode(part, basic_type) do
          {:cont, {:ok, {[decoded | acc_decoded], offset, rest_bytes}}}
        end
      else
        get_next_offset(acc_decoded, acc_rest_bytes, basic_type, offset, binary, first_offset)
      end
    end)
  end

  @spec get_next_offset(list, binary, any, integer(), binary, integer()) ::
          {:cont, {:ok, {list, integer(), binary}}} | {:halt, {:error, String.t()}}
  defp get_next_offset(acc_decoded, acc_rest_bytes, basic_type, offset, binary, first_offset) do
    <<next_offset::integer-32-little, rest_bytes::bitstring>> = acc_rest_bytes

    case sanitize_offset(next_offset, offset, byte_size(binary), first_offset) do
      {:ok, next_offset} ->
        part = :binary.part(binary, offset, next_offset - offset)

        with {:ok, decoded} <- decode(part, basic_type) do
          {:cont, {:ok, {[decoded | acc_decoded], next_offset, rest_bytes}}}
        end

      {:error, error} ->
        {:halt, {:error, error}}
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

  defp get_fixed_size(:bool), do: 1
  defp get_fixed_size({:int, size}), do: div(size, @bits_per_byte)

  defp variable_size?({:list, _, _}), do: true
  defp variable_size?(:bool), do: false
  defp variable_size?({:int, _}), do: false
end
