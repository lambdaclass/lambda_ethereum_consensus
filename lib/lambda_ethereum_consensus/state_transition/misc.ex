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
    result =
      if index >= index_count or index_count == 0 do
        {:error, "index not less than index count"}
      else
        shuffle_round_count = ChainSpec.get("SHUFFLE_ROUND_COUNT")

        new_index =
          Enum.reduce(0..(shuffle_round_count - 1), index, fn round, current_index ->
            round_as_bytes = <<round>>

            hash_of_seed_round = :crypto.hash(:sha256, seed <> round_as_bytes)

            pivot = rem(bytes_to_uint64(hash_of_seed_round), index_count)

            flip = rem(pivot + index_count - current_index, index_count)
            position = max(current_index, flip)

            position_div_256 = uint_to_bytes4(div(position, 256))

            source =
              :crypto.hash(:sha256, seed <> round_as_bytes <> position_div_256)

            byte_index = div(rem(position, 256), 8)
            byte = source |> :binary.bin_to_list() |> Enum.fetch!(byte_index)
            right_shift = byte >>> rem(position, 8)
            bit = rem(right_shift, 2)

            current_index =
              if bit == 1 do
                flip
              else
                current_index
              end

            current_index
          end)

        {:ok, new_index}
      end

    result
  end

  @spec increase_inactivity_score(SszTypes.uint64(), integer, MapSet.t(), SszTypes.uint64()) ::
          SszTypes.uint64()
  def increase_inactivity_score(
        inactivity_score,
        index,
        unslashed_participating_indices,
        inactivity_score_bias
      ) do
    if MapSet.member?(unslashed_participating_indices, index) do
      inactivity_score - min(1, inactivity_score)
    else
      inactivity_score + inactivity_score_bias
    end
  end

  @spec decrease_inactivity_score(SszTypes.uint64(), boolean, SszTypes.uint64()) ::
          SszTypes.uint64()
  def decrease_inactivity_score(
        inactivity_score,
        state_is_in_inactivity_leak,
        inactivity_score_recovery_rate
      ) do
    if state_is_in_inactivity_leak do
      inactivity_score
    else
      inactivity_score - min(inactivity_score_recovery_rate, inactivity_score)
    end
  end

  @spec update_inactivity_score(%{integer => SszTypes.uint64()}, integer, {SszTypes.uint64()}) ::
          SszTypes.uint64()
  def update_inactivity_score(updated_eligible_validator_indices, index, inactivity_score) do
    case Map.fetch(updated_eligible_validator_indices, index) do
      {:ok, new_eligible_validator_index} -> new_eligible_validator_index
      :error -> inactivity_score
    end
  end

  @doc """
  Return the start slot of ``epoch``.
  """
  @spec compute_start_slot_at_epoch(SszTypes.epoch()) :: SszTypes.slot()
  def compute_start_slot_at_epoch(epoch) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")
    epoch * slots_per_epoch
  end

  @spec bytes_to_uint64(binary()) :: SszTypes.uint64()
  defp bytes_to_uint64(value) do
    # Converts a binary value to a 64-bit unsigned integer
    <<first_8_bytes::binary-size(8), _::binary>> = value
    first_8_bytes |> :binary.decode_unsigned(:little)
  end

  @spec uint_to_bytes4(integer()) :: SszTypes.bytes4()
  defp uint_to_bytes4(value) do
    # Converts an unsigned integer value to a bytes 4 value
    <<value::32>> |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin()
  end
end
