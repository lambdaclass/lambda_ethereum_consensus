defmodule LambdaEthereumConsensus.ForkChoice do
  @moduledoc """
    The Store is responsible for tracking information required for the fork choice algorithm.
  """

  require Logger
  alias BeaconApi.EventPubSub
  alias LambdaEthereumConsensus.Execution.ExecutionChain
  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.ForkChoice.Head
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.P2P.Gossip.OperationsCollector
  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.BlobDb
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.BlockStates
  alias LambdaEthereumConsensus.Store.StateDb
  alias LambdaEthereumConsensus.Store.StoreDb
  alias Types.Attestation
  alias Types.BlockInfo
  alias Types.Store

  ##########################
  ### Public API
  ##########################

  # Persist the store asynchronously to avoid blocking the Libp2pPort GenServer.
  # On mainnet, :erlang.term_to_binary + eleveldb.write can stall for minutes
  # during LevelDB compaction, causing message queue explosion (observed 54K+ msgs).
  #
  # During catch-up sync (head_slot far behind wall clock), persist is skipped
  # entirely because:
  #   1. Deep-copying the Store struct (1.2M latest_messages) to a new process
  #      takes 1-9 seconds and can cause OOM on 62 GB systems
  #   2. LevelDB is already under heavy write pressure from state/block writes
  #   3. The store can be recovered from checkpoint + replay if the node crashes
  #
  # Once caught up (<= 2 slots behind), persists once per epoch at mid-epoch
  # (slot mod 32 == 16). We must avoid slots near epoch boundaries because:
  #   - slot mod 32 == 0: epoch processing uses peak memory (rewards, merkleization)
  #   - slot mod 32 == 1: epoch memory hasn't been GC'd yet
  # Mid-epoch gives maximum time for GC to reclaim epoch processing memory.
  @slots_per_epoch 32
  @max_behind_slots 2
  defp async_persist_store(store) do
    current_slot = compute_current_slot(store.time, store.genesis_time)
    head_slot = store.head_slot || 0
    catching_up? = current_slot - head_slot > @max_behind_slots

    cond do
      catching_up? ->
        # Skip persist during catch-up to avoid OOM and reduce memory pressure
        :skip

      rem(head_slot, @slots_per_epoch) == 16 ->
        # Persist at mid-epoch. Serializes in-process (avoids Store deep-copy
        # which takes 15s + 3-5 GB), then spawns only the LevelDB write.
        StoreDb.persist_store_async(store)

      true ->
        :skip
    end
  end

  @spec init_store(Store.t(), Types.uint64()) :: Store.t()
  def init_store(%Store{head_slot: head_slot, head_root: head_root} = store, time) do
    Logger.info("[Fork choice] Initialized store.", slot: head_slot)

    store =
      store
      |> Handlers.on_tick(time)
      |> rebuild_tree()

    :telemetry.execute([:sync, :store], %{slot: get_current_slot(store)})
    :telemetry.execute([:sync, :on_block], %{slot: store.head_slot})

    Metrics.block_status(head_root, head_slot, :transitioned)

    tap(store, &StoreDb.persist_store/1)
  end

  @spec on_block(Store.t(), BlockInfo.t()) :: {:ok, Store.t()} | {:error, String.t(), Store.t()}
  def on_block(store, %BlockInfo{} = block_info) do
    total_start = System.monotonic_time(:millisecond)
    slot = block_info.signed_block.message.slot
    block_root = block_info.root

    Logger.info("[Fork choice] Adding new block", root: block_info.root, slot: slot)

    %Store{finalized_checkpoint: last_finalized_checkpoint} = store

    result = process_block(block_info, store)

    case result do
      {:ok, new_store, timings} ->
        {new_store, timings} =
          StateTransition.timed(:recompute_head, timings, fn ->
            recompute_head(new_store, block_root, slot)
          end)

        new_store = prune_old_states(new_store, last_finalized_checkpoint.epoch)

        {_, timings} =
          StateTransition.timed(:store_persist, timings, fn ->
            async_persist_store(new_store)
          end)

        total = System.monotonic_time(:millisecond) - total_start
        timings = Map.put(timings, :total, total)

        :telemetry.execute([:sync, :on_block], %{slot: slot})
        emit_block_log(slot, block_root, timings)
        emit_block_metrics(slot, timings)

        EventPubSub.publish(:block, %{root: block_root, slot: slot})

        Logger.info("[Fork choice] Recomputed head",
          slot: new_store.head_slot,
          root: new_store.head_root
        )

        {:ok, new_store}

      {:error, reason} ->
        Logger.error("[Fork choice] Failed to add block: #{reason}",
          slot: slot,
          root: block_root
        )

        {:error, reason, store}
    end
  end

  @spec on_attestation(Store.t(), Types.Attestation.t()) :: Store.t()
  def on_attestation(store, %Attestation{} = attestation) do
    id = attestation.signature |> Base.encode16() |> String.slice(0, 8)
    Logger.debug("[Fork choice] Adding attestation #{id} to the store")

    store =
      case Handlers.on_attestation(store, attestation, false) do
        {:ok, new_store} -> new_store
        _ -> store
      end

    tap(store, &async_persist_store/1)
  end

  @spec on_attester_slashing(Store.t(), Types.AttesterSlashing.t()) :: Store.t()
  def on_attester_slashing(store, attester_slashing) do
    Logger.info("[Fork choice] Adding attester slashing to the store")

    case Handlers.on_attester_slashing(store, attester_slashing) do
      {:ok, new_store} ->
        tap(new_store, &async_persist_store/1)

      _ ->
        Logger.error("[Fork choice] Failed to add attester slashing to the store")
        store
    end
  end

  @spec on_tick(Store.t(), Types.uint64()) :: Store.t()
  def on_tick(store, time) do
    %Store{finalized_checkpoint: last_finalized_checkpoint} = store

    Handlers.on_tick(store, time)
    |> prune_old_states(last_finalized_checkpoint.epoch)
    |> tap(&async_persist_store/1)
  end

  @spec get_current_slot(Types.Store.t()) :: Types.slot()
  def get_current_slot(%Types.Store{} = store),
    do: compute_current_slot(store.time, store.genesis_time)

  @doc """
  Get the current chain slot based on the system time.

  There is just 1 use of this function outside this module:
   - In the Helpers.block_root_by_block_id/1 function
  """
  @spec get_current_chain_slot() :: Types.slot()
  def get_current_chain_slot(genesis_time \\ StoreDb.fetch_genesis_time!()),
    do: compute_current_slot(:os.system_time(:second), genesis_time)

  @doc """
  Check if a slot is in the future with respect to the systems time.
  """
  @spec future_slot?(Types.Store.t(), Types.slot()) :: boolean()
  def future_slot?(%Types.Store{} = store, slot) do
    if get_current_slot(store) < get_current_chain_slot(store.genesis_time) do
      # If the store store slot is in the past, we can safely assume that MAXIMUM_GOSSIP_CLOCK_DISPARITY
      # will not make a difference, store time is updated once every second and disparity is just 500ms.
      get_current_slot(store) < slot
    else
      # If the store slot is not in the past we need to take the actual system time in milliseconds
      # to calculate the current slot, having in mind the MAXIMUM_GOSSIP_CLOCK_DISPARITY.
      :os.system_time(:millisecond)
      |> compute_currents_slots_within_disparity(store.genesis_time)
      |> Enum.all?(fn possible_slot -> possible_slot < slot end)
    end
  end

  @spec get_finalized_checkpoint() :: Types.Checkpoint.t()
  def get_finalized_checkpoint() do
    %{finalized_checkpoint: finalized} = fetch_store!()
    finalized
  end

  @spec get_justified_checkpoint() :: Types.Checkpoint.t()
  def get_justified_checkpoint() do
    %{justified_checkpoint: justified} = fetch_store!()
    justified
  end

  @spec get_fork_digest() :: Types.fork_digest()
  def get_fork_digest() do
    get_current_chain_slot()
    |> compute_fork_digest(ChainSpec.get_genesis_validators_root())
  end

  @spec get_fork_digest_for_slot(Types.slot()) :: binary()
  def get_fork_digest_for_slot(slot) do
    compute_fork_digest(slot, ChainSpec.get_genesis_validators_root())
  end

  @spec get_fork_version() :: Types.version()
  def get_fork_version() do
    get_current_chain_slot()
    |> Misc.compute_epoch_at_slot()
    |> ChainSpec.get_fork_version_for_epoch()
  end

  @doc """
  Builds the EnrForkId struct for the current epoch using the EIP-7892 fork digest.
  Sets next_fork_epoch to the next BLOB_SCHEDULE epoch (on Fulu+) or FAR_FUTURE_EPOCH.
  """
  @spec compute_enr_fork_id() :: Types.EnrForkId.t()
  def compute_enr_fork_id() do
    current_epoch = get_current_chain_slot() |> Misc.compute_epoch_at_slot()
    genesis_validators_root = ChainSpec.get_genesis_validators_root()
    fork_digest = Misc.compute_fork_digest(genesis_validators_root, current_epoch)
    current_version = ChainSpec.get_fork_version_for_epoch(current_epoch)

    next_fork_epoch =
      if HardForkAliasInjection.fulu?() do
        case Misc.next_digest_change_epoch(current_epoch) do
          nil -> Constants.far_future_epoch()
          epoch -> epoch
        end
      else
        Constants.far_future_epoch()
      end

    %Types.EnrForkId{
      fork_digest: fork_digest,
      next_fork_version: current_version,
      next_fork_epoch: next_fork_epoch
    }
  end

  @spec get_current_status_message() :: Types.StatusMessage.t()
  def get_current_status_message(), do: get_current_status_message(fetch_store!())

  @spec get_current_status_message(Store.t()) :: Types.StatusMessage.t()
  def get_current_status_message(%{
        head_root: head_root,
        head_slot: head_slot,
        finalized_checkpoint: %{root: finalized_root, epoch: finalized_epoch}
      }) do
    %Types.StatusMessage{
      fork_digest: compute_fork_digest(head_slot, ChainSpec.get_genesis_validators_root()),
      finalized_root: finalized_root,
      finalized_epoch: finalized_epoch,
      head_root: head_root,
      head_slot: head_slot
    }
  end

  @spec get_current_status_message_v2() :: Types.StatusMessageV2.t()
  def get_current_status_message_v2(), do: get_current_status_message_v2(fetch_store!())

  @spec get_current_status_message_v2(Store.t()) :: Types.StatusMessageV2.t()
  def get_current_status_message_v2(%{
        head_root: head_root,
        head_slot: head_slot,
        finalized_checkpoint: %{root: finalized_root, epoch: finalized_epoch}
      }) do
    earliest_available_slot = finalized_epoch * ChainSpec.get("SLOTS_PER_EPOCH")

    %Types.StatusMessageV2{
      fork_digest: compute_fork_digest(head_slot, ChainSpec.get_genesis_validators_root()),
      finalized_root: finalized_root,
      finalized_epoch: finalized_epoch,
      head_root: head_root,
      head_slot: head_slot,
      earliest_available_slot: earliest_available_slot
    }
  end

  ##########################
  ### Private Functions
  ##########################

  # On startup, the persisted Store may have an empty tree_cache (e.g. after a crash
  # before StoreDb.persist_store ran, or after checkpoint sync). Rebuild it from the
  # durable :transitioned blocks in BlockDb so LMD-GHOST can trace the chain.
  @spec rebuild_tree(Store.t()) :: Store.t()
  defp rebuild_tree(store) do
    case Blocks.get_blocks_with_status(:transitioned) do
      {:ok, []} ->
        store

      {:ok, transitioned} ->
        Logger.info(
          "[Fork choice] Rebuilding tree_cache from #{length(transitioned)} transitioned blocks."
        )

        rebuilt =
          transitioned
          |> Enum.sort_by(& &1.signed_block.message.slot)
          |> Enum.reduce(store, fn block_info, acc ->
            Store.store_block_info(acc, block_info)
          end)

        try do
          Store.update_head_info(rebuilt)
        rescue
          e ->
            Logger.warning(
              "[Fork choice] Failed to recompute head after tree rebuild: #{inspect(e)}"
            )

            rebuilt
        end

      {:error, reason} ->
        Logger.warning(
          "[Fork choice] Failed to load transitioned blocks for tree rebuild: #{reason}"
        )

        store
    end
  end

  defp prune_old_states(store, last_finalized_epoch) do
    new_finalized_epoch = store.finalized_checkpoint.epoch

    if last_finalized_epoch < new_finalized_epoch do
      Logger.info("Pruning states before slot #{new_finalized_epoch}")

      new_finalized_slot =
        Misc.compute_start_slot_at_epoch(new_finalized_epoch)

      Task.Supervisor.start_child(
        PruneStatesSupervisor,
        fn -> StateDb.prune_states_older_than(new_finalized_slot) end
      )

      Task.Supervisor.start_child(
        PruneBlocksSupervisor,
        fn -> BlockDb.prune_blocks_older_than(new_finalized_slot) end
      )

      Task.Supervisor.start_child(
        PruneBlobsSupervisor,
        fn -> BlobDb.prune_old_blobs(new_finalized_slot) end
      )
    end

    Store.prune(store)
  end

  def apply_handler(iter, state, handler) do
    iter
    |> Enum.reduce_while({:ok, state}, fn
      x, {:ok, st} -> {:cont, handler.(st, x)}
      _, {:error, _} = err -> {:halt, err}
    end)
  end

  @spec process_block(BlockInfo.t(), Store.t()) ::
          {:ok, Store.t(), StateTransition.timings()} | {:error, String.t()}
  def process_block(%BlockInfo{signed_block: signed_block} = block_info, store) do
    attestations = signed_block.message.body.attestations
    attester_slashings = signed_block.message.body.attester_slashings
    block_slot = signed_block.message.slot
    wall_slot = get_current_chain_slot(store.genesis_time)

    # During catch-up (>4 slots behind), skip expensive prefetch_states and
    # attestation processing. Prefetching checkpoint states from LevelDB takes
    # 28-35s per block (300MB BeaconState deserialization), and committee
    # computation takes 10s. Attestation processing has no value during catch-up
    # since LMD-GHOST is already skipped. Using a small threshold (4 slots)
    # instead of SLOTS_PER_EPOCH prevents the 25-35s prefetch_states cost at
    # every epoch boundary during the transition from catch-up to normal mode.
    catching_up? = wall_slot - block_slot > 4

    {states, timings} =
      if catching_up? do
        {[], %{}}
      else
        prefetch_states_and_committees(store, attestations)
      end

    # Re-touch the parent state in ETS so its TTL is fresh. This prevents
    # eviction of the parent state during both prefetch_states (which can take
    # seconds) and catch-up mode (where rapid sequential block processing can
    # fill the 10-entry LRU cache, evicting the parent before the next block
    # needs it). Without this, cache misses fall through to LevelDB reads
    # that take 30s-10min+ on mainnet (775MB state deserialization + compaction).
    BlockStates.touch(signed_block.message.parent_root)

    new_store = update_in(store.checkpoint_states, fn cs -> Map.merge(cs, Map.new(states)) end)

    on_block_opts = if catching_up?, do: [skip_pulled_up_tip: true], else: []

    with {:ok, new_store, handler_timings} <- apply_on_block(new_store, block_info, on_block_opts) do
      timings = Map.merge(timings, handler_timings)

      if catching_up? do
        # Skip attestation processing during catch-up — attestations from old
        # blocks don't contribute to fork choice when LMD-GHOST is skipped.
        {:ok, new_store, timings}
      else
        with {:ok, new_store, timings} <- process_attestations(new_store, attestations, timings),
             {:ok, new_store, timings} <-
               process_attester_slashings(new_store, attester_slashings, timings) do
          {:ok, new_store, timings}
        end
      end
    end
  end

  defp prefetch_states_and_committees(store, attestations) do
    # Prefetch relevant states.
    {states, timings} =
      StateTransition.timed(:prefetch_states, %{}, fn ->
        attestations
        |> Enum.map(& &1.data.target)
        |> Enum.uniq()
        |> Enum.flat_map(fn ch -> fetch_checkpoint_state(store, ch) end)
      end)

    # Prefetch committees for all relevant epochs.
    {_, timings} =
      StateTransition.timed(:prefetch_committees, timings, fn ->
        for {checkpoint, state} <- states do
          Accessors.maybe_prefetch_committees(state, checkpoint.epoch)
        end
      end)

    {states, timings}
  end

  def fetch_checkpoint_state(store, checkpoint) do
    # Use cached-only fetch to avoid blocking the ForkChoice GenServer
    # with 28-85s LevelDB reads for 775MB mainnet BeaconStates.
    # If the state isn't in memory/ETS, we skip this checkpoint's attestations
    # rather than stalling block processing for up to 85 seconds.
    case Store.get_checkpoint_state_cached(store, checkpoint) do
      {_store, nil} -> []
      {_store, state} -> [{checkpoint, state}]
    end
  end

  defp apply_on_block(store, block_info, opts \\ []) do
    Handlers.on_block(store, block_info, opts)
  end

  defp process_attester_slashings(store, attester_slashings, timings) do
    {result, timings} =
      StateTransition.timed(:attester_slashings, timings, fn ->
        apply_handler(attester_slashings, store, &Handlers.on_attester_slashing/2)
      end)

    case result do
      {:ok, store} -> {:ok, store, timings}
      err -> err
    end
  end

  defp process_attestations(store, attestations, timings) do
    {result, timings} =
      StateTransition.timed(:attestations, timings, fn ->
        apply_handler(
          attestations,
          store,
          &Handlers.on_attestation(&1, &2, true)
        )
      end)

    case result do
      {:ok, store} -> {:ok, store, timings}
      err -> err
    end
  end

  # Recomputes the head in the store and sends the new head to others (libP2P,
  # operations collector db, execution chain db).
  @spec recompute_head(Store.t(), Types.root(), Types.slot()) :: Store.t()
  defp recompute_head(store, block_root, block_slot) do
    wall_slot = get_current_chain_slot(store.genesis_time)

    head_root =
      if wall_slot - block_slot > 1 do
        # When behind the chain tip (>1 slot), head is the latest processed
        # block. Skip expensive LMD-GHOST (~3-4s) since during catch-up there
        # are no competing forks — we only have the canonical chain from peers.
        block_root
      else
        {:ok, root} = Head.get_head(store)
        root
      end

    # Cache-only — avoid blocking Libp2pPort on LevelDB reads.
    head_block = Blocks.get_block_cached(head_root)

    if head_block do
      Handlers.notify_forkchoice_update(store, head_block)

      %{slot: slot, body: body} = head_block

      OperationsCollector.notify_new_block(head_block)
      Libp2pPort.notify_new_head(slot, head_root)
      ExecutionChain.notify_new_block(slot, body.eth1_data, body.execution_payload)
    end

    slot = if head_block, do: head_block.slot, else: store.head_slot || 0

    Logger.debug("[Fork choice] Updated fork choice cache", slot: slot)

    Store.update_head_info(store, slot, head_root)
  end

  defp emit_block_log(slot, root, timings) do
    hex_root = root |> Base.encode16() |> String.slice(0, 8)
    has_epoch = Map.has_key?(timings, :"epoch.justification_and_finalization")

    pairs =
      timings
      |> Enum.sort_by(fn {_k, v} -> v end, :desc)
      |> Enum.map_join(" ", fn {k, v} -> "#{k}=#{v}ms" end)

    Logger.info("[on_block] slot=#{slot} root=#{hex_root} epoch=#{has_epoch} #{pairs}")
  end

  defp emit_block_metrics(_slot, timings) do
    # Map timing keys to the original handler/transition/operation metadata
    # that Metrics.span_operation used to emit via :telemetry.span.
    for {key, ms} <- timings do
      {handler, transition, operation} = timing_key_metadata(key)

      :telemetry.execute(
        [:fork_choice, :latency, :stop],
        %{duration: ms * 1_000_000},
        %{handler: handler, transition: transition, operation: operation}
      )
    end
  end

  # Maps timing key atoms back to the {handler, transition, operation} metadata
  # that the old Metrics.span_operation calls used.
  defp timing_key_metadata(key) do
    key_str = Atom.to_string(key)

    cond do
      String.starts_with?(key_str, "epoch.") ->
        op = key_str |> String.replace_prefix("epoch.", "") |> String.to_atom()
        {:on_block, :epoch, op}

      String.starts_with?(key_str, "block.") ->
        op = key_str |> String.replace_prefix("block.", "") |> String.to_atom()
        {:on_block, :process_block, op}

      true ->
        {key, nil, nil}
    end
  end

  defp fetch_store!() do
    {:ok, store} = StoreDb.fetch_store()
    store
  end

  defp compute_current_slot(time, genesis_time),
    do: div(time - genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))

  defp compute_currents_slots_within_disparity(time_ms, genesis_time) do
    min_time = div(time_ms - ChainSpec.get("MAXIMUM_GOSSIP_CLOCK_DISPARITY"), 1000)
    max_time = div(time_ms + ChainSpec.get("MAXIMUM_GOSSIP_CLOCK_DISPARITY"), 1000)

    [
      compute_current_slot(min_time, genesis_time),
      compute_current_slot(max_time, genesis_time)
    ]
  end

  defp compute_fork_digest(slot, genesis_validators_root) do
    epoch = Misc.compute_epoch_at_slot(slot)
    Misc.compute_fork_digest(genesis_validators_root, epoch)
  end
end
