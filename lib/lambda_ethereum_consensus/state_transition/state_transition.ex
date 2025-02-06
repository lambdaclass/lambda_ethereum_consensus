defmodule LambdaEthereumConsensus.StateTransition do
  @moduledoc """
  State transition logic.
  """

  require Logger
  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.EpochProcessing
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Operations
  alias Types.BeaconState
  alias Types.BeaconBlockHeader
  alias Types.BlockInfo
  alias Types.SignedBeaconBlock
  alias Types.StateInfo

  import LambdaEthereumConsensus.Utils, only: [map_ok: 2]

  @spec verified_transition(BeaconState.t(), BlockInfo.t()) ::
          {:ok, StateInfo.t()} | {:error, String.t()}
  def verified_transition(beacon_state, block_info) do
    beacon_state
    |> transition(block_info.signed_block)
    # Verify signature
    |> map_ok(fn st ->
      if block_signature_valid?(st, block_info.signed_block) do
        {:ok, st}
      else
        {:error, "invalid block signature"}
      end
    end)
    |> map_ok(fn new_state ->
      with {:ok, state_info} <-
             StateInfo.from_beacon_state(new_state, block_root: block_info.root) do
        if block_info.signed_block.message.state_root == state_info.root do
          {:ok, state_info}
        else
          {:error, "mismatched state roots"}
        end
      end
    end)
  end

  @spec transition(BeaconState.t(), SignedBeaconBlock.t()) :: {:ok, BeaconState.t()}
  def transition(beacon_state, signed_block) do
    block = signed_block.message

    beacon_state
    # Process slots (including those with no blocks) since block
    |> process_slots(block.slot)
    # Process block
    |> map_ok(&process_block(&1, block))
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
    slots_per_historical_root = ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")
    cache_index = rem(state.slot, slots_per_historical_root)
    cache_state_root = Enum.at(state.state_roots, cache_index)

    state =
      if cache_state_root || cache_state_root == <<0::256>> do
        Logger.error("State root not already cached at index #{cache_index}")

        previous_state_root = Ssz.hash_tree_root!(state)
        roots = List.replace_at(state.state_roots, cache_index, previous_state_root)
        state = %BeaconState{state | state_roots: roots}

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

        previous_block_root = Ssz.hash_tree_root!(state.latest_block_header)
        roots = List.replace_at(state.block_roots, cache_index, previous_block_root)

        %BeaconState{state | block_roots: roots}
      else
        state
      end

    end_time = System.monotonic_time(:millisecond)
    Logger.info("[Slot processing] took #{(end_time - start_time) / 1000} s")

    {:ok, state}
  end

  defp process_epoch(%BeaconState{} = state) do
    start_time = System.monotonic_time(:millisecond)

    state
    |> EpochProcessing.process_justification_and_finalization()
    |> epoch_op(:inactivity_updates, &EpochProcessing.process_inactivity_updates/1)
    |> epoch_op(:rewards_and_penalties, &EpochProcessing.process_rewards_and_penalties/1)
    |> epoch_op(:registry_updates, &EpochProcessing.process_registry_updates/1)
    |> epoch_op(:slashings, &EpochProcessing.process_slashings/1)
    |> epoch_op(:eth1_data_reset, &EpochProcessing.process_eth1_data_reset/1)
    |> epoch_op(:effective_balance_updates, &EpochProcessing.process_effective_balance_updates/1)
    |> epoch_op(:slashings_reset, &EpochProcessing.process_slashings_reset/1)
    |> epoch_op(:randao_mixes_reset, &EpochProcessing.process_randao_mixes_reset/1)
    |> epoch_op(
      :historical_summaries_update,
      &EpochProcessing.process_historical_summaries_update/1
    )
    |> epoch_op(
      :participation_flag_updates,
      &EpochProcessing.process_participation_flag_updates/1
    )
    |> epoch_op(:sync_committee_updates, &EpochProcessing.process_sync_committee_updates/1)
    |> tap(fn _ ->
      end_time = System.monotonic_time(:millisecond)
      Logger.info("[Epoch processing] took #{(end_time - start_time) / 1000} s")
    end)
  end

  def block_signature_valid?(%BeaconState{} = state, %SignedBeaconBlock{} = signed_block) do
    proposer = Aja.Vector.at!(state.validators, signed_block.message.proposer_index)
    domain = Accessors.get_domain(state, Constants.domain_beacon_proposer())
    signing_root = Misc.compute_signing_root(signed_block.message, domain)
    Bls.valid?(proposer.pubkey, signing_root, signed_block.signature)
  end

  # defp time(res, label, fun) do
  #   start_time = System.monotonic_time(:millisecond)
  #   res = fun.(res)
  #   end_time = System.monotonic_time(:millisecond)
  #   Logger.info("[#{label}] took #{(end_time - start_time) / 1000} s")
  #   res
  # end

  def process_block(state, block) do
    start_time = System.monotonic_time(:millisecond)

    {:ok, state}
    |> block_op(:block_header, &Operations.process_block_header(&1, block))
    # |> time(:header, fn res ->
    #   block_op(res, :block_header, &Operations.process_block_header(&1, block))
    # end)
    |> block_op(:withdrawals, &Operations.process_withdrawals(&1, block.body.execution_payload))
    # |> time(:withdrawals, fn res ->
    #   block_op(
    #     res,
    #     :withdrawals,
    #     &Operations.process_withdrawals(&1, block.body.execution_payload)
    #   )
    # end)
    |> block_op(:execution_payload, &Operations.process_execution_payload(&1, block.body))
    # |> time(:execution_payload, fn res ->
    #   block_op(res, :execution_payload, &Operations.process_execution_payload(&1, block.body))
    # end)
    |> block_op(:randao, &Operations.process_randao(&1, block.body))
    # |> time(:randao, fn res ->
    #   block_op(res, :randao, &Operations.process_randao(&1, block.body))
    # end)
    |> block_op(:eth1_data, &Operations.process_eth1_data(&1, block.body))
    # |> time(:eth1_data, fn res ->
    #   block_op(res, :eth1_data, &Operations.process_eth1_data(&1, block.body))
    # end)
    |> map_ok(&Operations.process_operations(&1, block.body))
    # |> time(:operations, fn res -> map_ok(res, &Operations.process_operations(&1, block.body)) end)
    |> block_op(
      :sync_aggregate,
      &Operations.process_sync_aggregate(&1, block.body.sync_aggregate)
    )
    # |> time(:sync_aggregate, fn res ->
    #   block_op(
    #     res,
    #     :sync_aggregate,
    #     &Operations.process_sync_aggregate(&1, block.body.sync_aggregate)
    #   )
    # end)
    |> tap(fn _ ->
      end_time = System.monotonic_time(:millisecond)
      Logger.info("[Block processing] took #{(end_time - start_time) / 1000} s")
    end)
  end

  def block_op(state, operation, f), do: apply_op(state, :process_block, operation, f)
  def epoch_op(state, operation, f), do: apply_op(state, :epoch, operation, f)

  def apply_op(state, transition, operation, f) do
    Metrics.span_operation(:on_block, transition, operation, fn -> map_ok(state, f) end)
  end
end
