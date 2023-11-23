defmodule LambdaEthereumConsensus.StateTransition do
  @moduledoc """
  State transition logic.
  """

  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.{EpochProcessing, Operations}
  alias SszTypes.{BeaconBlockHeader, BeaconState, SignedBeaconBlock}

  import LambdaEthereumConsensus.Utils, only: [if_then_update: 3, map: 2]

  @spec state_transition(BeaconState.t(), SignedBeaconBlock.t(), boolean()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def state_transition(
        %BeaconState{} = state,
        %SignedBeaconBlock{message: block} = signed_block,
        _validate_result
      ) do
    # NOTE: we aren't in a state to make validations yet
    validate_result = false

    state
    # Process slots (including those with no blocks) since block
    |> process_slots(block.slot)
    # Verify signature
    |> if_then_update(validate_result, fn state ->
      if verify_block_signature(state, signed_block) do
        {:ok, state}
      else
        {:error, "invalid block signature"}
      end
    end)
    # Process block
    |> map(&process_block(&1, block))
    # Verify state root
    |> map(
      &if_then_update(&1, validate_result, fn state ->
        if block.state_root != Ssz.hash_tree_root!(state) do
          {:error, "mismatched state roots"}
        else
          {:ok, state}
        end
      end)
    )
  end

  def process_slots(%BeaconState{slot: old_slot}, slot) when old_slot >= slot,
    do: {:error, "slot is older than state"}

  def process_slots(%BeaconState{slot: old_slot} = state, slot) do
    Enum.reduce((old_slot + 1)..slot, state, fn next_slot, state ->
      state
      |> process_slot()
      # Process epoch on the start slot of the next epoch
      |> if_then_update(rem(next_slot, ChainSpec.get("SLOTS_PER_EPOCH")) == 0, &process_epoch/1)
      |> then(&%BeaconState{&1 | slot: next_slot})
    end)
  end

  defp process_slot(%BeaconState{} = state) do
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
    %BeaconState{state | block_roots: roots}
  end

  defp process_epoch(%BeaconState{} = state) do
    state
    |> EpochProcessing.process_justification_and_finalization()
    |> map(&EpochProcessing.process_inactivity_updates/1)
    |> map(&EpochProcessing.process_rewards_and_penalties/1)
    |> map(&EpochProcessing.process_registry_updates/1)
    |> map(&EpochProcessing.process_slashings/1)
    |> map(&EpochProcessing.process_eth1_data_reset/1)
    |> map(&EpochProcessing.process_effective_balance_updates/1)
    |> map(&EpochProcessing.process_slashings_reset/1)
    |> map(&EpochProcessing.process_randao_mixes_reset/1)
    |> map(&EpochProcessing.process_historical_summaries_update/1)
    |> map(&EpochProcessing.process_participation_flag_updates/1)

    # |> map(&EpochProcessing.process_sync_committee_updates/1)
  end

  def verify_block_signature(%BeaconState{} = state, %SignedBeaconBlock{} = signed_block) do
    proposer = Enum.at(state.validators, signed_block.message.proposer_index)

    signing_root =
      StateTransition.Misc.compute_signing_root(
        signed_block.message,
        StateTransition.Accessors.get_domain(state, Constants.domain_beacon_proposer())
      )

    Bls.valid?(proposer.pubkey, signing_root, signed_block.signature)
  end

  # TODO: uncomment when implemented
  def process_block(state, block) do
    {:ok, state}
    # |> map(&Operations.process_block_header(&1, block))
    |> map(&Operations.process_withdrawals(&1, block.body.execution_payload))
    # |> map(&Operations.process_execution_payload(&1, block.body, EXECUTION_ENGINE))
    # |> map(&Operations.process_randao(&1, block.body))
    # |> map(&Operations.process_eth1_data(&1, block.body))
    # |> map(&Operations.process_operations(&1, block.body))
    |> map(&Operations.process_sync_aggregate(&1, block.body.sync_aggregate))
  end
end
