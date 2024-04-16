defmodule LambdaEthereumConsensus.StateTransition.Shuffling do
  @moduledoc """
  Shuffling state transition functions
  """
  require Aja
  import Bitwise

  @seed_size 32
  @position_size 4

  @doc """
  Performs a full shuffle of a list of indices.
  This function is equivalent to running `compute_shuffled_index` for each index in the list.

  Shuffling the whole list should be 10-100x faster than shuffling each single item.

  ## Examples
    iex> shuffled = Shuffling.shuffle_list(Aja.Vector.new(0..99), <<0::32*8>>)
    iex> {:ok, new_index } = Misc.compute_shuffled_index(54, 100, <<0::32*8>>)
    iex> shuffled |> Aja.Enum.at(54) == new_index
    true
  """
  @spec shuffle_list(Aja.Vector.t(), binary()) :: Aja.Vector.t()

  def shuffle_list(_input, seed) when byte_size(seed) != @seed_size do
    raise("Seed must be #{@seed_size} bytes long")
  end

  def shuffle_list(input, _seed) when Aja.vec_size(input) == 0 do
    input
  end

  def shuffle_list(input, seed) do
    rounds = ChainSpec.get("SHUFFLE_ROUND_COUNT")
    shuffle_list(input, rounds - 1, seed)
  end

  @spec shuffle_list(Aja.Vector.t(), non_neg_integer(), binary()) ::
          Aja.Vector.t()

  defp shuffle_list(input, round, _seed) when round < 0, do: input

  defp shuffle_list(input, round, seed) do
    input_size = Aja.Enum.count(input)

    round_bytes =
      :binary.encode_unsigned(round, :little)

    pivot =
      (seed <> round_bytes)
      |> SszEx.hash()
      |> :binary.part(0, 8)
      |> :binary.decode_unsigned(:little)
      |> rem(input_size)

    mirror = (pivot + 1) >>> 1
    source = (seed <> round_bytes <> position_bytes(pivot >>> 8)) |> SszEx.hash()
    byte_v = :binary.at(source, (pivot &&& 0xFF) >>> 3)

    {_source, _byte_v, input} =
      Enum.reduce(0..(mirror - 1)//1, {source, byte_v, input}, fn i, {source, byte_v, input} ->
        j = pivot - i

        source = source(seed, round_bytes, j, source)
        byte_v = byte_v(source, j, byte_v)
        bit_v = bit_v(byte_v, j)

        input =
          if bit_v == 1 do
            swap_values(input, i, j)
          else
            input
          end

        {source, byte_v, input}
      end)

    mirror = (pivot + input_size + 1) >>> 1
    list_end = input_size - 1
    source = (seed <> round_bytes <> position_bytes(list_end >>> 8)) |> SszEx.hash()
    byte_v = :binary.at(source, (list_end &&& 0xFF) >>> 3)

    {_source, _byte_v, input} =
      Enum.reduce((pivot + 1)..(mirror - 1)//1, {source, byte_v, input}, fn i,
                                                                            {source, byte_v,
                                                                             input} ->
        loop_iter = i - (pivot + 1)
        j = list_end - loop_iter

        source = source(seed, round_bytes, j, source)
        byte_v = byte_v(source, j, byte_v)
        bit_v = bit_v(byte_v, j)

        input =
          if bit_v == 1 do
            swap_values(input, i, j)
          else
            input
          end

        {source, byte_v, input}
      end)

    shuffle_list(input, round - 1, seed)
  end

  @spec position_bytes(integer()) :: binary()
  defp position_bytes(position) when position >= 0 do
    :binary.encode_unsigned(position, :little)
    |> pad_binary(@position_size)
    |> binary_part(0, @position_size)
  end

  defp source(seed, round_bytes, j, previous_source) do
    if (j &&& 0xFF) == 0xFF do
      (seed <> round_bytes <> position_bytes(j >>> 8)) |> SszEx.hash()
    else
      previous_source
    end
  end

  defp byte_v(source, j, previous_byte_v) do
    if (j &&& 0x07) == 0x07 do
      :binary.at(source, (j &&& 0xFF) >>> 3)
    else
      previous_byte_v
    end
  end

  defp bit_v(byte_v, j) do
    byte_v >>> (j &&& 0x07) &&& 0x01
  end

  defp pad_binary(binary, n) do
    byte_size = byte_size(binary)
    padding = max(n - byte_size, 0)
    <<binary::binary, 0::size(padding * 8)>>
  end

  def swap_values(list, i, j) do
    value_i = Aja.Enum.at(list, i)
    value_j = Aja.Enum.at(list, j)

    list
    |> Aja.Vector.replace_at(i, value_j)
    |> Aja.Vector.replace_at(j, value_i)
  end
end
