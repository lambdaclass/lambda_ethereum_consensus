defmodule LambdaEthereumConsensus.StateTransition do
  @moduledoc """
  State transition logic.
  """

  alias SszTypes.{BeaconBlockHeader, BeaconState, SignedBeaconBlock}

  def state_transition(
        %BeaconState{} = state,
        %SignedBeaconBlock{message: _block} = _signed_block,
        _validate_result
      ) do
    # TODO: implement
    state
  end

  def process_slots(%BeaconState{slot: old_slot}, slot) when old_slot >= slot,
    do: {:error, "slot is older than state"}

  def process_slots(%BeaconState{slot: old_slot} = state, slot) do
    Enum.reduce((old_slot + 1)..slot, state, fn next_slot, state ->
      state
      |> process_slot()
      # Process epoch on the start slot of the next epoch
      |> if_then_update(rem(next_slot, ChainSpec.get("SLOTS_PER_EPOCH") == 0), &process_epoch/1)
      |> then(&%BeaconState{&1 | slot: next_slot})
    end)
  end

  defp process_slot(%BeaconState{} = state) do
    # Cache state root
    previous_state_root = Ssz.hash_tree_root(state)
    slots_per_historical_root = ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")
    cache_index = rem(state.slot, slots_per_historical_root)
    roots = List.replace_at(state.state_roots, cache_index, previous_state_root)
    state = %BeaconState{state | state_roots: roots}

    # Cache latest block header state root
    state =
      if state.latest_block_header.state_root == <<0::256>> do
        block_header = %BeaconBlockHeader{
          state.latest_block_header
          | state_root: previous_state_root
        }

        %BeaconState{state | latest_block_header: block_header}
      else
        state
      end

    # Cache block root
    previous_block_root = Ssz.hash_tree_root(state.latest_block_header)
    roots = List.replace_at(state.block_roots, cache_index, previous_block_root)
    %BeaconState{state | block_roots: roots}
  end

  defp process_epoch(%BeaconState{} = state), do: state

  defp if_then_update(value, true, fun), do: fun.(value)
  defp if_then_update(value, false, _fun), do: value
end
