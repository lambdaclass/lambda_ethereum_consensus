defmodule LambdaEthereumConsensus.StateTransition do
  @moduledoc """
  State transition logic.
  """

  require Logger
  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.{EpochProcessing, Operations}
  alias Types.{BeaconBlockHeader, BeaconState, SignedBeaconBlock}

  import LambdaEthereumConsensus.Utils, only: [map_ok: 2]

  @spec state_transition(BeaconState.t(), SignedBeaconBlock.t(), boolean()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def state_transition(
        %BeaconState{} = state,
        %SignedBeaconBlock{message: block} = signed_block,
        validate_result
      ) do
    state
    # Process slots (including those with no blocks) since block
    |> process_slots(block.slot)
    # Verify signature
    |> map_ok(fn st ->
      if not validate_result or block_signature_valid?(st, signed_block) do
        {:ok, st}
      else
        {:error, "invalid block signature"}
      end
    end)
    # Process block
    |> map_ok(&process_block(&1, block))
    # Verify state root
    |> map_ok(fn st ->
      if not validate_result or block.state_root == Ssz.hash_tree_root!(st) do
        {:ok, st}
      else
        {:error, "mismatched state roots"}
      end
    end)
  end

  def process_slots(%BeaconState{slot: old_slot}, slot) when old_slot >= slot,
    do: {:error, "slot is older than state"}

  def process_slots(%BeaconState{slot: old_slot} = state, slot) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")

    Enum.reduce((old_slot + 1)..slot//1, {:ok, state}, fn next_slot, acc ->
      acc
      |> map_ok(&process_slot/1)
      # Process epoch on the start slot of the next epoch
      |> map_ok(&maybe_process_epoch(&1, rem(next_slot, slots_per_epoch)))
      |> map_ok(&{:ok, %BeaconState{&1 | slot: next_slot}})
    end)
  end

  defp maybe_process_epoch(%BeaconState{} = state, 0), do: process_epoch(state)
  defp maybe_process_epoch(%BeaconState{} = state, _slot_in_epoch), do: {:ok, state}

  defp process_slot(%BeaconState{} = state) do
    start_time = System.monotonic_time(:millisecond)

    # Cache state root
    previous_state_root = Ssz.hash_tree_root!(state)
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
    previous_block_root = Ssz.hash_tree_root!(state.latest_block_header)
    roots = List.replace_at(state.block_roots, cache_index, previous_block_root)

    end_time = System.monotonic_time(:millisecond)
    Logger.debug("[Slot processing] took #{end_time - start_time} ms")

    {:ok, %BeaconState{state | block_roots: roots}}
  end

  defp process_epoch(%BeaconState{} = state) do
    start_time = System.monotonic_time(:millisecond)

    state
    |> EpochProcessing.process_justification_and_finalization()
    |> map_ok(&EpochProcessing.process_inactivity_updates/1)
    |> map_ok(&EpochProcessing.process_rewards_and_penalties/1)
    |> map_ok(&EpochProcessing.process_registry_updates/1)
    |> map_ok(&EpochProcessing.process_slashings/1)
    |> map_ok(&EpochProcessing.process_eth1_data_reset/1)
    |> map_ok(&EpochProcessing.process_effective_balance_updates/1)
    |> map_ok(&EpochProcessing.process_slashings_reset/1)
    |> map_ok(&EpochProcessing.process_randao_mixes_reset/1)
    |> map_ok(&EpochProcessing.process_historical_summaries_update/1)
    |> map_ok(&EpochProcessing.process_participation_flag_updates/1)
    |> map_ok(&EpochProcessing.process_sync_committee_updates/1)
    |> tap(fn _ ->
      end_time = System.monotonic_time(:millisecond)
      Logger.debug("[Epoch processing] took #{end_time - start_time} ms")
    end)
  end

  def block_signature_valid?(%BeaconState{} = state, %SignedBeaconBlock{} = signed_block) do
    proposer = Aja.Vector.at!(state.validators, signed_block.message.proposer_index)
    domain = StateTransition.Accessors.get_domain(state, Constants.domain_beacon_proposer())
    signing_root = StateTransition.Misc.compute_signing_root(signed_block.message, domain)
    Bls.valid?(proposer.pubkey, signing_root, signed_block.signature)
  end

  def process_block(state, block) do
    start_time = System.monotonic_time(:millisecond)

    {:ok, state}
    |> map_ok(&Operations.process_block_header(&1, block))
    |> map_ok(&Operations.process_withdrawals(&1, block.body.execution_payload))
    |> map_ok(&Operations.process_execution_payload(&1, block.body))
    |> map_ok(&Operations.process_randao(&1, block.body))
    |> map_ok(&Operations.process_eth1_data(&1, block.body))
    |> map_ok(&Operations.process_operations(&1, block.body))
    |> map_ok(&Operations.process_sync_aggregate(&1, block.body.sync_aggregate))
    |> tap(fn _ ->
      end_time = System.monotonic_time(:millisecond)
      Logger.debug("[Block processing] took #{end_time - start_time} ms")
    end)
  end
end
