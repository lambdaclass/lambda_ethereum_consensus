defmodule LambdaEthereumConsensus.StateTransition do
  @moduledoc """
  State transition logic.
  """

  require Logger
  require HardForkAliasInjection
  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.EpochProcessing
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Operations
  alias Types.BeaconState
  alias Types.BlockInfo
  alias Types.SignedBeaconBlock
  alias Types.StateInfo

  import LambdaEthereumConsensus.Utils, only: [map_ok: 2]

  @spec verified_transition(StateInfo.t() | BeaconState.t(), BlockInfo.t()) ::
          {:ok, StateInfo.t()} | {:error, String.t()}
  def verified_transition(%StateInfo{} = state_info, block_info) do
    previous_roots = %{
      # We store the roots indexed by slot number to ensure slot matches when reusing them.
      state_info.beacon_state.slot => %{
        state_root: state_info.root,
        block_root: state_info.block_root
      }
    }

    verified_transition(state_info.beacon_state, block_info, previous_roots)
  end

  def verified_transition(%BeaconState{} = state, block_info, previous_roots \\ %{}) do
    state
    |> transition(block_info.signed_block, previous_roots)
    # Verify signature
    |> map_ok(fn st ->
      if block_signature_valid?(st, block_info.signed_block) do
        {:ok, st}
      else
        {:error, "invalid block signature"}
      end
    end)
    |> map_ok(fn new_state ->
      with {:ok, new_state_info} <-
             StateInfo.from_beacon_state(new_state, block_root: block_info.root) do
        if block_info.signed_block.message.state_root == new_state_info.root do
          {:ok, new_state_info}
        else
          {:error, "mismatched state roots"}
        end
      end
    end)
  end

  @spec transition(BeaconState.t(), SignedBeaconBlock.t()) :: {:ok, BeaconState.t()}
  def transition(beacon_state, signed_block, previous_roots \\ %{}) do
    block = signed_block.message

    beacon_state
    # Process slots (including those with no blocks) since block
    |> process_slots(block.slot, previous_roots)
    # Process block
    |> map_ok(&process_block(&1, block))
  end

  def process_slots(state, slot, previous_roots \\ %{})

  def process_slots(%BeaconState{slot: old_slot}, slot, _previous_roots) when old_slot >= slot,
    do: {:error, "slot is older than state"}

  def process_slots(%BeaconState{slot: old_slot} = state, slot, previous_roots) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")

    Enum.reduce((old_slot + 1)..slot//1, {:ok, state}, fn next_slot, acc ->
      acc
      |> map_ok(&apply_process_slot(&1, previous_roots))
      # Process epoch on the first slot of the next epoch
      |> map_ok(&maybe_process_epoch(&1, rem(next_slot, slots_per_epoch)))
      |> map_ok(&{:ok, %{&1 | slot: next_slot}})
      # Apply fork upgrade at the first slot of FULU_FORK_EPOCH (if compiled for Fulu)
      |> map_ok(&maybe_upgrade_to_fulu(&1, next_slot))
    end)
  end

  # Fulu fork upgrade: triggered at the first slot of FULU_FORK_EPOCH.
  # On Electra builds this is compiled away (on_fulu expands to the else branch).
  defp maybe_upgrade_to_fulu(%BeaconState{} = state, next_slot) do
    HardForkAliasInjection.on_fulu do
      if next_slot == Misc.compute_start_slot_at_epoch(ChainSpec.get("FULU_FORK_EPOCH")) do
        upgrade_to_fulu(state)
      else
        {:ok, state}
      end
    else
      {:ok, state}
    end
  end

  # Spec: upgrade_to_fulu(pre) in fulu/fork.md
  # Fulu adds proposer_lookahead (EIP-7917) and updates the fork version.
  defp upgrade_to_fulu(%BeaconState{fork: %{current_version: current_version}} = state) do
    epoch = Accessors.get_current_epoch(state)

    new_fork = %Types.Fork{
      previous_version: current_version,
      current_version: ChainSpec.get("FULU_FORK_VERSION"),
      epoch: epoch
    }

    state = %BeaconState{state | fork: new_fork}

    # Spec: proposer_lookahead=initialize_proposer_lookahead(pre)
    with {:ok, lookahead} <- initialize_proposer_lookahead(state) do
      {:ok, %BeaconState{state | proposer_lookahead: lookahead}}
    end
  end

  # Spec: initialize_proposer_lookahead (fulu/fork.md)
  # Computes proposer indices for current..current+MIN_SEED_LOOKAHEAD epochs.
  defp initialize_proposer_lookahead(%BeaconState{} = state) do
    current_epoch = Accessors.get_current_epoch(state)
    min_seed_lookahead = ChainSpec.get("MIN_SEED_LOOKAHEAD")

    0..min_seed_lookahead
    |> Enum.reduce_while({:ok, []}, fn i, {:ok, acc} ->
      case Accessors.get_beacon_proposer_indices(state, current_epoch + i) do
        {:ok, indices} -> {:cont, {:ok, acc ++ indices}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp maybe_process_epoch(%BeaconState{} = state, 0), do: process_epoch(state)
  defp maybe_process_epoch(%BeaconState{} = state, _slot_in_epoch), do: {:ok, state}

  defp apply_process_slot(state, previous_roots) do
    Metrics.span_operation(:process_slot, nil, nil, fn -> process_slot(state, previous_roots) end)
  end

  defp process_slot(%BeaconState{} = state, previous_roots) do
    start_time = System.monotonic_time(:millisecond)

    slot_previous_roots = Map.get(previous_roots, state.slot, nil)

    # Cache state root
    previous_state_root =
      if slot_previous_roots do
        Logger.debug("Slot #{state.slot}: previous state root in cache",
          root: slot_previous_roots.state_root
        )

        slot_previous_roots.state_root
      else
        Logger.debug("Slot #{state.slot}: no previous state root in cache")
        Ssz.hash_tree_root!(state)
      end

    slots_per_historical_root = ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")
    cache_index = rem(state.slot, slots_per_historical_root)
    roots = List.replace_at(state.state_roots, cache_index, previous_state_root)
    state = %BeaconState{state | state_roots: roots}

    # Cache latest block header state root
    state =
      if state.latest_block_header.state_root == <<0::256>> do
        block_header = %{
          state.latest_block_header
          | state_root: previous_state_root
        }

        %BeaconState{state | latest_block_header: block_header}
      else
        state
      end

    # Cache block root
    previous_block_root =
      if slot_previous_roots do
        Logger.debug("Slot #{state.slot}, previous block root in cache",
          root: slot_previous_roots.block_root
        )

        slot_previous_roots.block_root
      else
        Logger.debug("Slot #{state.slot}, no previous block root in cache")
        Ssz.hash_tree_root!(state.latest_block_header)
      end

    roots = List.replace_at(state.block_roots, cache_index, previous_block_root)

    end_time = System.monotonic_time(:millisecond)
    Logger.debug("[Slot processing] took #{end_time - start_time} ms")

    {:ok, %BeaconState{state | block_roots: roots}}
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
    |> epoch_op(:pending_deposits, &EpochProcessing.process_pending_deposits/1)
    |> epoch_op(:pending_consolidations, &EpochProcessing.process_pending_consolidations/1)
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
    |> maybe_proposer_lookahead()
    |> tap(fn _ ->
      end_time = System.monotonic_time(:millisecond)
      Logger.debug("[Epoch processing] took #{end_time - start_time} ms")
    end)
  end

  # Only run process_proposer_lookahead on Fulu (EIP-7917).
  # Compiled away on Electra builds.
  defp maybe_proposer_lookahead(state) do
    if HardForkAliasInjection.fulu?() do
      epoch_op(state, :proposer_lookahead, &EpochProcessing.process_proposer_lookahead/1)
    else
      state
    end
  end

  def block_signature_valid?(%BeaconState{} = state, %SignedBeaconBlock{} = signed_block) do
    proposer = Aja.Vector.at!(state.validators, signed_block.message.proposer_index)
    domain = Accessors.get_domain(state, Constants.domain_beacon_proposer())
    signing_root = Misc.compute_signing_root(signed_block.message, domain)
    Bls.valid?(proposer.pubkey, signing_root, signed_block.signature)
  end

  def process_block(state, block) do
    start_time = System.monotonic_time(:millisecond)

    {:ok, state}
    |> block_op(:block_header, &Operations.process_block_header(&1, block))
    |> block_op(:withdrawals, &Operations.process_withdrawals(&1, block.body.execution_payload))
    |> block_op(:execution_payload, &Operations.process_execution_payload(&1, block.body))
    |> block_op(:randao, &Operations.process_randao(&1, block.body))
    |> block_op(:eth1_data, &Operations.process_eth1_data(&1, block.body))
    |> map_ok(&Operations.process_operations(&1, block.body))
    |> block_op(
      :sync_aggregate,
      &Operations.process_sync_aggregate(&1, block.body.sync_aggregate)
    )
    |> tap(fn _ ->
      end_time = System.monotonic_time(:millisecond)
      Logger.debug("[Block processing] took #{end_time - start_time} ms")
    end)
  end

  def block_op(state, operation, f), do: apply_op(state, :process_block, operation, f)
  def epoch_op(state, operation, f), do: apply_op(state, :epoch, operation, f)

  def apply_op(state, transition, operation, f) do
    Metrics.span_operation(:on_block, transition, operation, fn -> map_ok(state, f) end)
  end
end
