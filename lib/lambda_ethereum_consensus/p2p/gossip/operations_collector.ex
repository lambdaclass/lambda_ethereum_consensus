defmodule LambdaEthereumConsensus.P2P.Gossip.OperationsCollector do
  @moduledoc """
  Module that stores the operations received from gossipsub.
  """

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils
  alias LambdaEthereumConsensus.Utils.BitField

  require Logger

  @behaviour Handler

  @operation_prefix "operation"
  @slot_prefix "operation_slot"

  @operations [
    :bls_to_execution_change,
    :attester_slashing,
    :proposer_slashing,
    :voluntary_exit,
    :attestation,
    :sync_committee_contribution
  ]

  @topic_msgs [
    "beacon_aggregate_and_proof",
    "voluntary_exit",
    "proposer_slashing",
    "attester_slashing",
    "bls_to_execution_change",
    "sync_committee_contribution_and_proof"
  ]

  def subscribe_to_topics() do
    Enum.reduce_while(topics(), :ok, fn topic, _acc ->
      case Libp2pPort.subscribe_to_topic(topic, __MODULE__) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, "[OperationsCollector] Subscription failed: '#{reason}'"}}
      end
    end)
  end

  @spec get_bls_to_execution_changes(non_neg_integer()) ::
          list(Types.SignedBLSToExecutionChange.t())
  def get_bls_to_execution_changes(count) do
    get_operation(:bls_to_execution_change, count)
  end

  @spec get_attester_slashings(non_neg_integer()) :: list(Types.AttesterSlashing.t())
  def get_attester_slashings(count) do
    get_operation(:attester_slashing, count)
  end

  @spec get_proposer_slashings(non_neg_integer()) :: list(Types.ProposerSlashing.t())
  def get_proposer_slashings(count) do
    get_operation(:proposer_slashing, count)
  end

  @spec get_voluntary_exits(non_neg_integer()) :: list(Types.SignedVoluntaryExit.t())
  def get_voluntary_exits(count) do
    get_operation(:voluntary_exit, count)
  end

  @spec get_attestations(non_neg_integer(), Types.slot()) :: list(Types.Attestation.t())
  def get_attestations(count, slot) do
    slot = slot || fetch_slot!()
    get_operation(:attestation, count, &ignore?(&1, slot))
  end

  @spec get_sync_committee_contributions() :: list(Types.SignedContributionAndProof.t())
  def get_sync_committee_contributions() do
    get_operation(:sync_committee_contribution, :all)
  end

  @spec notify_new_block(Types.BeaconBlock.t()) :: :ok
  def notify_new_block(%Types.BeaconBlock{} = block) do
    indices =
      block.body.bls_to_execution_changes
      |> MapSet.new(& &1.message.validator_index)

    update_operation(:bls_to_execution_change, fn values ->
      Enum.reject(values, &MapSet.member?(indices, &1.message.validator_index))
    end)

    # TODO: improve AttesterSlashing filtering
    update_operation(:attester_slashing, fn values ->
      Enum.reject(values, &Enum.member?(block.body.attester_slashings, &1))
    end)

    slashed_proposers =
      block.body.proposer_slashings |> MapSet.new(& &1.signed_header_1.message.proposer_index)

    update_operation(:proposer_slashing, fn values ->
      Enum.reject(
        values,
        &MapSet.member?(slashed_proposers, &1.signed_header_1.message.proposer_index)
      )
    end)

    exited = block.body.voluntary_exits |> MapSet.new(& &1.message.validator_index)

    update_operation(:voluntary_exit, fn values ->
      Enum.reject(values, &MapSet.member?(exited, &1.message.validator_index))
    end)

    # TODO: improve attestation filtering
    added_attestations = MapSet.new(block.body.attestations)

    update_operation(:attestation, fn values ->
      Stream.reject(values, &MapSet.member?(added_attestations, &1))
      |> Enum.reject(&old_attestation?(&1, block.slot))
    end)

    # We only keep the last contributions for each slot, past ones are not needed
    # since they are not included in the block when it is built.
    update_operation(:sync_committee_contribution, fn values ->
      Enum.reject(values, &(&1.message.contribution.slot < block.slot))
    end)

    store_slot(block.slot)
  end

  @doc """
  1. Joins all the necessary topics (`@topic_msgs`)
  2. Initializes the tables in the db by creating and storing empty operations.
  """
  def init() do
    topics = topics()
    Enum.each(topics, &Libp2pPort.join_topic/1)
    store_slot(nil)
    Enum.each(@operations, fn operation -> store_operation(operation, []) end)
  end

  defp get_operation(operation, count) when operation in @operations do
    # NOTE: we don't remove these from the db, since after a block is built
    #  :new_block will be called, and already added messages will be removed
    operation
    |> fetch_operation!()
    |> cap_operations(count)
  end

  defp get_operation(operation, count, filter) when operation in @operations do
    operation
    |> fetch_operation!()
    |> Stream.reject(filter)
    |> cap_operations(count)
  end

  defp cap_operations(%Stream{} = operations, :all), do: Enum.to_list(operations)
  defp cap_operations(operations, :all), do: operations
  defp cap_operations(operations, count), do: Enum.take(operations, count)

  @impl true
  def handle_gossip_message(store, topic, msg_id, message) do
    handle_gossip_message(topic, msg_id, message)
    store
  end

  def handle_gossip_message(
        <<_::binary-size(15)>> <> "beacon_aggregate_and_proof" <> _,
        _msg_id,
        message
      ) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok,
          %Types.SignedAggregateAndProof{message: %Types.AggregateAndProof{aggregate: aggregate}}} <-
           Ssz.from_ssz(uncompressed, Types.SignedAggregateAndProof) do
      Logger.debug(
        "[Gossip] Aggregate decoded. Total attestations: #{BitField.count(aggregate.aggregation_bits)}",
        slot: aggregate.data.slot,
        root: aggregate.data.beacon_block_root
      )

      # We are getting ~500 attestations in half a second. This is overwhelming the store GenServer at the moment.
      # ForkChoice.on_attestation(aggregate)
      handle_msg({:attestation, aggregate})
    end
  end

  def handle_gossip_message(
        <<_::binary-size(15)>> <> "voluntary_exit" <> _,
        _msg_id,
        message
      ) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.SignedVoluntaryExit{} = signed_voluntary_exit} <-
           Ssz.from_ssz(uncompressed, Types.SignedVoluntaryExit) do
      handle_msg({:voluntary_exit, signed_voluntary_exit})
    end
  end

  def handle_gossip_message(
        <<_::binary-size(15)>> <> "proposer_slashing" <> _,
        _msg_id,
        message
      ) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.ProposerSlashing{} = proposer_slashing} <-
           Ssz.from_ssz(uncompressed, Types.ProposerSlashing) do
      handle_msg({:proposer_slashing, proposer_slashing})
    end
  end

  def handle_gossip_message(
        <<_::binary-size(15)>> <> "attester_slashing" <> _,
        _msg_id,
        message
      ) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.AttesterSlashing{} = attester_slashing} <-
           Ssz.from_ssz(uncompressed, Types.AttesterSlashing) do
      handle_msg({:attester_slashing, attester_slashing})
    end
  end

  def handle_gossip_message(
        <<_::binary-size(15)>> <> "bls_to_execution_change" <> _,
        _msg_id,
        message
      ) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.SignedBLSToExecutionChange{} = bls_to_execution_change} <-
           Ssz.from_ssz(uncompressed, Types.SignedBLSToExecutionChange) do
      handle_msg({:bls_to_execution_change, bls_to_execution_change})
    end
  end

  def handle_gossip_message(
        <<_::binary-size(15)>> <> "sync_committee_contribution_and_proof" <> _,
        msg_id,
        message
      ) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.SignedContributionAndProof{} = contribution_and_proof} <-
           Ssz.from_ssz(uncompressed, Types.SignedContributionAndProof) do
      # TODO: (#1291) validate before accepting
      Libp2pPort.validate_message(msg_id, :accept)

      handle_msg({:sync_committee_contribution, contribution_and_proof})
    end
  end

  def topics() do
    fork_context = ForkChoice.get_fork_digest() |> Base.encode16(case: :lower)

    topics =
      Enum.map(@topic_msgs, fn topic_msg ->
        "/eth2/#{fork_context}/#{topic_msg}/ssz_snappy"
      end)

    topics
  end

  # TODO: filter duplicates
  defp handle_msg({operation, msg})
       when operation in @operations do
    new_msgs = [msg | fetch_operation!(operation)]
    store_operation(operation, new_msgs)
  end

  defp old_attestation?(%Types.Attestation{data: data}, slot) do
    current_epoch = Misc.compute_epoch_at_slot(slot + 1)
    data.target.epoch not in [current_epoch, current_epoch - 1]
  end

  defp ignore?(%Types.Attestation{}, nil), do: false

  defp ignore?(%Types.Attestation{data: data}, slot) do
    # Right now this preset is 1, so we add every attestation ASAP, but it could be changed in the future
    data.slot + ChainSpec.get("MIN_ATTESTATION_INCLUSION_DELAY") > slot
  end

  defp update_operation(operation, f) when is_function(f) do
    fetch_operation!(operation)
    |> f.()
    |> then(&store_operation(operation, &1))
  end

  defp store_operation(operation, value) do
    :telemetry.span([:db, :latency], %{}, fn ->
      {Db.put(
         Utils.get_key(@operation_prefix, Atom.to_string(operation)),
         :erlang.term_to_binary(value)
       ), %{module: "operations_collector", action: "persist"}}
    end)
  end

  defp fetch_operation!(operation) do
    {:ok, value} =
      :telemetry.span([:db, :latency], %{}, fn ->
        {Db.get(Utils.get_key(@operation_prefix, Atom.to_string(operation))),
         %{module: "operations_collector", action: "fetch"}}
      end)

    :erlang.binary_to_term(value)
  end

  defp store_slot(value) do
    :telemetry.span([:db, :latency], %{}, fn ->
      {Db.put(@slot_prefix, :erlang.term_to_binary(value)),
       %{module: "operations_collector", action: "persist"}}
    end)
  end

  defp fetch_slot!() do
    {:ok, value} =
      :telemetry.span([:db, :latency], %{}, fn ->
        {Db.get(@slot_prefix), %{module: "operations_collector", action: "fetch"}}
      end)

    :erlang.binary_to_term(value)
  end
end
