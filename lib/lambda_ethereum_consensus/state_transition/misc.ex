defmodule LambdaEthereumConsensus.StateTransition.Misc do
  @moduledoc """
  Misc functions
  """
  import Bitwise

  @doc """
  Returns the epoch number at slot.
  """
  @spec compute_epoch_at_slot(SszTypes.slot()) :: SszTypes.epoch()
  def compute_epoch_at_slot(slot) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")
    div(slot, slots_per_epoch)
  end

  @doc """
     Return the shuffled index corresponding to ``seed`` (and ``index_count``).
  """
  @spec compute_shuffled_index(SszTypes.uint64(), SszTypes.uint64(), SszTypes.bytes32()) ::
          {:ok, SszTypes.uint64()} | {:error, String.t()}
  def compute_shuffled_index(index, index_count, seed) do
    unless index < index_count do
      {:error, "index not less than index count"}
    end

    shuffle_round_count = ChainSpec.get("SHUFFLE_ROUND_COUNT")

    new_index =
      Enum.reduce(0..(shuffle_round_count - 1), index, fn round, current_index ->
        round_as_bytes =
          <<round::8>> |> :binary.decode_unsigned() |> :binary.encode_unsigned(:little)

        seed_as_bytes = seed |> :binary.decode_unsigned() |> :binary.encode_unsigned(:little)
        hash_of_seed_round = :crypto.hash(:sha256, seed_as_bytes <> round_as_bytes)

        first_8_bytes_of_hash_of_seed_round =
          hash_of_seed_round |> :binary.bin_to_list({0, 8}) |> :binary.list_to_bin()

        pivot = :binary.decode_unsigned(first_8_bytes_of_hash_of_seed_round, :little)

        flip = rem(pivot + index_count - current_index, index_count)
        position = max(current_index, flip)

        position_div_256 =
          <<div(position, 256)::32>>
          |> :binary.decode_unsigned()
          |> :binary.encode_unsigned(:little)

        source = :crypto.hash(:sha256, seed_as_bytes <> round_as_bytes <> position_div_256)
        byte_index = div(rem(position, 256), 8)
        byte = source |> :binary.bin_to_list() |> Enum.fetch!(byte_index)
        right_shift = byte >>> rem(position, 8)
        bit = rem(right_shift, 2)

        index =
          if bit !== 0 do
            flip
          else
            current_index
          end

        {:ok, index}
      end)

    new_index
  end
end
