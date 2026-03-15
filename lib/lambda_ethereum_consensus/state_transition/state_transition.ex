defmodule LambdaEthereumConsensus.StateTransition do
  @moduledoc """
  State transition logic.
  """

  require Logger
  require HardForkAliasInjection
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.EpochProcessing
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Operations
  alias Types.BeaconState
  alias Types.BlockInfo
  alias Types.SignedBeaconBlock
  alias Types.StateInfo

  @type timings :: %{atom() => non_neg_integer()}

  @doc """
  Times `fun`, storing the elapsed milliseconds under `label` in `timings`.
  If `label` already exists, the durations are summed (useful for repeated calls like slot processing).
  Returns `{result_of_fun, updated_timings}`.
  """
  @spec timed(atom(), timings(), (-> result)) :: {result, timings()} when result: any()
  def timed(label, timings, fun) do
    start = System.monotonic_time(:millisecond)
    result = fun.()
    elapsed = System.monotonic_time(:millisecond) - start
    {result, Map.update(timings, label, elapsed, &(&1 + elapsed))}
  end

  @spec verified_transition(StateInfo.t() | BeaconState.t(), BlockInfo.t()) ::
          {:ok, StateInfo.t(), timings()} | {:error, String.t()}
  def verified_transition(%StateInfo{} = state_info, block_info) do
    previous_roots = %{
      # We store the roots indexed by slot number to ensure slot matches when reusing them.
      state_info.beacon_state.slot => %{
        state_root: state_info.root,
        block_root: state_info.block_root
      }
    }

    verified_transition(
      state_info.beacon_state,
      block_info,
      previous_roots,
      state_info.field_hashes
    )
  end

  def verified_transition(
        %BeaconState{} = state,
        block_info,
        previous_roots \\ %{},
        prev_field_hashes \\ %{}
      ) do
    with {:ok, st, timings} <- transition(state, block_info.signed_block, previous_roots) do
      {sig_result, timings} =
        timed(:signature_verify, timings, fn ->
          if block_signature_valid?(st, block_info.signed_block),
            do: {:ok, st},
            else: {:error, "invalid block signature"}
        end)

      with {:ok, st} <- sig_result do
        # Determine which field hashes can be reused from the previous state.
        # On epoch boundary blocks, most fields change — don't cache anything.
        # On non-epoch blocks, cache expensive fields that don't change.
        cached_field_hashes =
          cacheable_field_hashes(timings, block_info.signed_block.message, prev_field_hashes)

        # Try incremental hashing for large Aja.Vector fields: collect changed indices
        # from the block, apply them to the cached tree, and put hashes in cached_field_hashes.
        # This avoids the expensive Aja.Vector.to_list + NIF decode for 2.2M entries.
        # Pass prev_field_hashes so the NIF can validate the cache matches the parent fork.
        cached_field_hashes =
          maybe_incremental_balance_hash(
            cached_field_hashes,
            timings,
            block_info.signed_block.message,
            st,
            prev_field_hashes
          )

        cached_field_hashes =
          maybe_incremental_participation_hash(
            cached_field_hashes,
            timings,
            block_info.signed_block.message,
            st,
            prev_field_hashes
          )

        cached_field_hashes =
          maybe_incremental_randao_hash(
            cached_field_hashes,
            timings,
            block_info.signed_block.message,
            st,
            prev_field_hashes
          )

        {merkle_result, timings} =
          timed(:merkleization, timings, fn ->
            StateInfo.from_beacon_state(st,
              block_root: block_info.root,
              cached_field_hashes: cached_field_hashes
            )
          end)

        with {:ok, new_state_info} <- merkle_result do
          if block_info.signed_block.message.state_root == new_state_info.root do
            {:ok, new_state_info, timings}
          else
            {:error, "mismatched state roots"}
          end
        end
      end
    end
  end

  # Fields safe to cache on non-epoch blocks when no validator-modifying operations present.
  # These fields are only modified during epoch processing (not block operations):
  #  7 = historical_roots (frozen), 11 = validators, 14 = slashings,
  # 17 = justification_bits, 18 = previous_justified_checkpoint,
  # 19 = current_justified_checkpoint, 20 = finalized_checkpoint,
  # 21 = inactivity_scores, 22 = current_sync_committee,
  # 23 = next_sync_committee, 27 = historical_summaries, 37 = proposer_lookahead
  # NOTE: field 15 (previous_epoch_participation) is NOT cacheable — attestation
  # processing updates it on every block for previous-epoch attestations.
  @cacheable_non_epoch_fields [7, 11, 14, 17, 18, 19, 20, 21, 22, 23, 27, 37]

  # When block operations DO modify validators (slashings, exits, BLS changes,
  # consolidations, deposits), exclude fields also modified by those operations:
  # 11 = validators (slashings/exits/BLS changes), 14 = slashings (slash_validator),
  # 21 = inactivity_scores (add_validator_to_registry appends on new deposits)
  @cacheable_non_epoch_fields_no_validators [7, 17, 18, 19, 20, 22, 23, 27, 37]

  defp cacheable_field_hashes(_timings, _block, prev_field_hashes)
       when prev_field_hashes == %{},
       do: %{}

  defp cacheable_field_hashes(timings, block, prev_field_hashes) do
    # If epoch processing happened, don't cache anything (most fields change)
    epoch_processed? = Map.has_key?(timings, :"epoch.rewards_and_penalties")

    if epoch_processed? do
      %{}
    else
      fields =
        if block_modifies_validators?(block),
          do: @cacheable_non_epoch_fields_no_validators,
          else: @cacheable_non_epoch_fields

      Map.take(prev_field_hashes, fields)
    end
  end

  # Check if a block contains operations that can modify state.validators.
  # Slashings, exits, BLS-to-execution changes, withdrawal requests (full exits),
  # consolidation requests, and legacy deposits can all modify the validators vector.
  # Deposit requests (execution_requests.deposits) only modify pending_deposits, not validators.
  defp block_modifies_validators?(block) do
    body = block.body

    body.proposer_slashings != [] or
      body.attester_slashings != [] or
      body.voluntary_exits != [] or
      body.bls_to_execution_changes != [] or
      body.deposits != [] or
      body.execution_requests.withdrawals != [] or
      body.execution_requests.consolidations != []
  end

  # Try to compute the balance field hash incrementally by passing only changed
  # balance indices to the Rust NIF, avoiding the expensive Aja.Vector.to_list
  # + NIF decode for 2.2M balances. Falls back gracefully on cache miss.
  defp maybe_incremental_balance_hash(
         cached_field_hashes,
         timings,
         block,
         state,
         prev_field_hashes
       ) do
    epoch_processed? = Map.has_key?(timings, :"epoch.rewards_and_penalties")
    prev_hash = Map.get(prev_field_hashes, 12)

    if epoch_processed? or cached_field_hashes == %{} or is_nil(prev_hash) do
      cached_field_hashes
    else
      case collect_changed_balance_indices(block, state) do
        {:ok, indices} ->
          updates =
            indices
            |> Enum.uniq()
            |> Enum.map(fn idx -> {idx, Aja.Vector.at!(state.balances, idx)} end)

          case Ssz.update_balance_cache(
                 updates,
                 Aja.Vector.size(state.balances),
                 prev_hash
               ) do
            {:ok, hash} -> Map.put(cached_field_hashes, 12, hash)
            {:error, :cache_miss} -> cached_field_hashes
          end

        :skip ->
          cached_field_hashes
      end
    end
  end

  # Collect all validator indices whose balances changed during block processing.
  # Sources: sync committee (512), withdrawals (<=16), proposer rewards, slashings.
  defp collect_changed_balance_indices(block, state) do
    # If slashings occurred, the slashed validator's balance changes AND the
    # whistleblower/proposer reward is spread — hard to track precisely. Skip.
    if block.body.proposer_slashings != [] or block.body.attester_slashings != [] do
      :skip
    else
      epoch = Accessors.get_current_epoch(state)

      # Sync committee indices: look up from ETS cache (populated by process_sync_aggregate)
      sync_indices =
        case Accessors.get_block_root_at_slot(
               state,
               max(Misc.compute_start_slot_at_epoch(epoch), 1) - 1
             ) do
          {:ok, root} ->
            case :ets.lookup(:sync_committee_indices, {epoch, root}) do
              [{{^epoch, ^root}, indices}] -> indices
              [] -> :miss
            end

          _ ->
            :miss
        end

      case sync_indices do
        :miss ->
          :skip

        indices when is_list(indices) ->
          # Withdrawal validator indices
          withdrawal_indices =
            Enum.map(block.body.execution_payload.withdrawals, & &1.validator_index)

          # Proposer gets rewards from sync aggregate + attestations
          {:ok, Enum.concat([indices, withdrawal_indices, [block.proposer_index]])}
      end
    end
  end

  # Try to compute the participation field hashes incrementally (fields 15, 16).
  # Collects attesting validator indices from the block's attestations, reads
  # their new participation values, and passes to the NIF for incremental update.
  defp maybe_incremental_participation_hash(
         cached_field_hashes,
         timings,
         block,
         state,
         prev_field_hashes
       ) do
    epoch_processed? = Map.has_key?(timings, :"epoch.rewards_and_penalties")

    if epoch_processed? or cached_field_hashes == %{} do
      cached_field_hashes
    else
      epoch = Accessors.get_current_epoch(state)

      # Collect attesting validator indices, split by target epoch
      {prev_indices, curr_indices} =
        collect_attesting_indices(block.body.attestations, state, epoch)

      cached_field_hashes =
        try_incremental_participation(
          cached_field_hashes,
          15,
          prev_indices,
          state.previous_epoch_participation,
          prev_field_hashes
        )

      try_incremental_participation(
        cached_field_hashes,
        16,
        curr_indices,
        state.current_epoch_participation,
        prev_field_hashes
      )
    end
  end

  defp try_incremental_participation(
         cached_field_hashes,
         field_num,
         indices,
         participation,
         prev_field_hashes
       ) do
    prev_hash = Map.get(prev_field_hashes, field_num)

    if is_nil(prev_hash) do
      cached_field_hashes
    else
      if indices == [] do
        # No changes to this participation field — pass empty updates to get current hash.
        case Ssz.update_participation_cache(
               field_num,
               [],
               Aja.Vector.size(participation),
               prev_hash
             ) do
          {:ok, hash} -> Map.put(cached_field_hashes, field_num, hash)
          {:error, :cache_miss} -> cached_field_hashes
        end
      else
        updates =
          indices
          |> Enum.uniq()
          |> Enum.map(fn idx -> {idx, Aja.Vector.at!(participation, idx)} end)

        case Ssz.update_participation_cache(
               field_num,
               updates,
               Aja.Vector.size(participation),
               prev_hash
             ) do
          {:ok, hash} -> Map.put(cached_field_hashes, field_num, hash)
          {:error, :cache_miss} -> cached_field_hashes
        end
      end
    end
  end

  # Try to compute the randao_mixes field hash incrementally (field 13).
  # Only 1 entry changes per block (current epoch's randao mix). Pass the index
  # and new value to the NIF to update just 16 nodes instead of hashing 65536 entries.
  defp maybe_incremental_randao_hash(
         cached_field_hashes,
         timings,
         _block,
         state,
         prev_field_hashes
       ) do
    epoch_processed? = Map.has_key?(timings, :"epoch.rewards_and_penalties")
    prev_hash = Map.get(prev_field_hashes, 13)

    if epoch_processed? or cached_field_hashes == %{} or is_nil(prev_hash) do
      cached_field_hashes
    else
      epoch = Accessors.get_current_epoch(state)
      epochs_per_historical_vector = ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR")
      index = rem(epoch, epochs_per_historical_vector)
      new_value = Aja.Vector.at!(state.randao_mixes, index)

      case Ssz.update_randao_cache(index, new_value, Aja.Vector.size(state.randao_mixes), prev_hash) do
        {:ok, hash} -> Map.put(cached_field_hashes, 13, hash)
        {:error, :cache_miss} -> cached_field_hashes
      end
    end
  end

  # Collect attesting validator indices from block attestations, split by target epoch.
  # Returns {previous_epoch_indices, current_epoch_indices}.
  # Uses cached beacon committees from ETS for efficient lookup.
  defp collect_attesting_indices(attestations, state, current_epoch) do
    Enum.reduce(attestations, {[], []}, fn att, {prev_acc, curr_acc} ->
      is_current = att.data.target.epoch == current_epoch

      case Accessors.get_attesting_indices(state, att) do
        {:ok, indices} ->
          idx_list = MapSet.to_list(indices)

          if is_current,
            do: {prev_acc, idx_list ++ curr_acc},
            else: {idx_list ++ prev_acc, curr_acc}

        _ ->
          {prev_acc, curr_acc}
      end
    end)
  end

  @spec transition(BeaconState.t(), SignedBeaconBlock.t()) ::
          {:ok, BeaconState.t(), timings()}
  def transition(beacon_state, signed_block, previous_roots \\ %{}) do
    block = signed_block.message

    with {:ok, state, slot_timings} <- process_slots(beacon_state, block.slot, previous_roots),
         {:ok, state, block_timings} <- process_block(state, block) do
      {:ok, state, Map.merge(slot_timings, block_timings)}
    end
  end

  def process_slots(state, slot, previous_roots \\ %{})

  def process_slots(%BeaconState{slot: old_slot}, slot, _previous_roots) when old_slot >= slot,
    do: {:error, "slot is older than state"}

  def process_slots(%BeaconState{slot: old_slot} = state, slot, previous_roots) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")

    Enum.reduce((old_slot + 1)..slot//1, {:ok, state, %{}}, fn next_slot, acc ->
      with {:ok, st, timings} <- acc do
        {slot_result, timings} =
          timed(:slot_processing, timings, fn ->
            process_slot(st, previous_roots)
          end)

        with {:ok, st} <- slot_result,
             {:ok, st, timings} <-
               maybe_process_epoch(st, rem(next_slot, slots_per_epoch), timings),
             {:ok, st} <- maybe_upgrade_to_fulu(%{st | slot: next_slot}, next_slot) do
          {:ok, st, timings}
        end
      end
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

  defp maybe_process_epoch(%BeaconState{} = state, 0, timings) do
    case process_epoch(state) do
      {:ok, state, epoch_timings} -> {:ok, state, Map.merge(timings, epoch_timings)}
      err -> err
    end
  end

  defp maybe_process_epoch(%BeaconState{} = state, _slot_in_epoch, timings),
    do: {:ok, state, timings}

  defp process_slot(%BeaconState{} = state, previous_roots) do
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

    {:ok, %BeaconState{state | block_roots: roots}}
  end

  defp process_epoch(%BeaconState{} = state) do
    {:ok, state, %{}}
    |> epoch_op(
      :justification_and_finalization,
      &EpochProcessing.process_justification_and_finalization/1
    )
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
    {:ok, state, %{}}
    |> block_op(:block_header, &Operations.process_block_header(&1, block))
    |> block_op(:withdrawals, &Operations.process_withdrawals(&1, block.body.execution_payload))
    |> block_op(:execution_payload, &Operations.process_execution_payload(&1, block.body))
    |> block_op(:randao, &Operations.process_randao(&1, block.body))
    |> block_op(:eth1_data, &Operations.process_eth1_data(&1, block.body))
    |> prefetch_committees_for_block()
    |> block_op(:operations, &Operations.process_operations(&1, block.body))
    |> block_op(
      :sync_aggregate,
      &Operations.process_sync_aggregate(&1, block.body.sync_aggregate)
    )
  end

  # Ensure beacon committees for the current epoch are cached before processing
  # attestations. Without this, each attestation triggers an expensive on-demand
  # committee computation (~650ms × 8 committees = ~5.2s per block). The full
  # epoch prefetch (~10s) amortizes to ~312ms per block across 32 blocks.
  defp prefetch_committees_for_block({:ok, state, timings}) do
    epoch = Misc.compute_epoch_at_slot(state.slot)

    {_, timings} =
      timed(:prefetch_committees, timings, fn ->
        Accessors.maybe_prefetch_committees(state, epoch)
      end)

    {:ok, state, timings}
  end

  defp prefetch_committees_for_block(err), do: err

  def epoch_op({:ok, state, timings}, operation, f) do
    key = :"epoch.#{operation}"

    {result, timings} = timed(key, timings, fn -> f.(state) end)

    case result do
      {:ok, new_state} -> {:ok, new_state, timings}
      {:error, _} = err -> err
    end
  end

  def epoch_op({:error, _} = err, _operation, _f), do: err

  def block_op({:ok, state, timings}, operation, f) do
    key = :"block.#{operation}"

    {result, timings} = timed(key, timings, fn -> f.(state) end)

    case result do
      {:ok, new_state} -> {:ok, new_state, timings}
      {:error, _} = err -> err
    end
  end

  def block_op({:error, _} = err, _operation, _f), do: err
end
