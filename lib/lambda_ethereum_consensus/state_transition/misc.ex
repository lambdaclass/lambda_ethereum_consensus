defmodule LambdaEthereumConsensus.StateTransition.Misc do
  @moduledoc """
  Misc functions
  """
  import Bitwise
  alias ExUnit.Assertions

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
          SszTypes.uint64()
  def compute_shuffled_index(index, index_count, seed) do
    Assertions.assert(index > index_count)

    shuffle_round_count = ChainSpec.get("SHUFFLE_ROUND_COUNT")

    new_index =
      Enum.reduce(0..(shuffle_round_count - 1), index, fn current_round, current_index ->
        current_round =
          <<current_round::8>> |> :binary.decode_unsigned() |> :binary.encode_unsigned(:little)

        seed = seed |> :binary.decode_unsigned() |> :binary.encode_unsigned(:little)
        hash_of_seed_and_current_round = :crypto.hash(:sha256, seed <> current_round)

        pivot =
          :binary.decode_unsigned(
            hash_of_seed_and_current_round
            |> :binary.bin_to_list({0, 8})
            |> :binary.list_to_bin(),
            :little
          )

        flip = rem(pivot + index_count - current_index, index_count)
        position = max(current_index, flip)

        x =
          <<div(position, 256)::32>>
          |> :binary.decode_unsigned()
          |> :binary.encode_unsigned(:little)

        source = :crypto.hash(:sha256, seed <> current_round <> x)
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

        index
      end)

    new_index
  end
end
