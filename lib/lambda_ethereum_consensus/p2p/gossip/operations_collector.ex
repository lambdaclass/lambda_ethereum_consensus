defmodule LambdaEthereumConsensus.P2P.Gossip.OperationsCollector do
  @moduledoc """
  Module that stores the operations received from gossipsub.
  """

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils
  alias LambdaEthereumConsensus.Utils.BitField
  alias Types.Attestation
  alias Types.AttesterSlashing
  alias Types.BeaconBlock
  alias Types.ProposerSlashing
  alias Types.SignedBLSToExecutionChange
  alias Types.SignedVoluntaryExit

  require Logger

  @behaviour Handler

  @operation_prefix "operation"
  @slot_prefix "operation_slot"

  @operations [
    :bls_to_execution_change,
    :attester_slashing,
    :proposer_slashing,
    :voluntary_exit,
    :attestation
  ]

  @topic_msgs [
    "beacon_aggregate_and_proof",
    "voluntary_exit",
    "proposer_slashing",
    "attester_slashing",
    "bls_to_execution_change"
  ]

  def start() do
    Enum.each(topics(), fn topic ->
      case Libp2pPort.subscribe_to_topic(topic, __MODULE__) do
        :ok ->
          :ok

        {:error, reason} ->
          raise "[OperationsCollector] Subscription failed: '#{reason}'"
      end
    end)
  end

  @spec get_bls_to_execution_changes(non_neg_integer()) :: list(SignedBLSToExecutionChange.t())
  def get_bls_to_execution_changes(count) do
    get_operation({:get, :bls_to_execution_change, count})
  end

  @spec get_attester_slashings(non_neg_integer()) :: list(AttesterSlashing.t())
  def get_attester_slashings(count) do
    get_operation({:get, :attester_slashing, count})
  end

  @spec get_proposer_slashings(non_neg_integer()) :: list(ProposerSlashing.t())
  def get_proposer_slashings(count) do
    get_operation({:get, :proposer_slashing, count})
  end

  @spec get_voluntary_exits(non_neg_integer()) :: list(SignedVoluntaryExit.t())
  def get_voluntary_exits(count) do
    get_operation({:get, :voluntary_exit, count})
  end

  @spec get_attestations(non_neg_integer()) :: list(Attestation.t())
  def get_attestations(count) do
    get_operation({:get, :attestation, count})
  end

  @spec notify_new_block(BeaconBlock.t()) :: :ok
  def notify_new_block(%BeaconBlock{} = block) do
    operations = %{
      bls_to_execution_changes: block.body.bls_to_execution_changes,
      attester_slashings: block.body.attester_slashings,
      proposer_slashings: block.body.proposer_slashings,
      voluntary_exits: block.body.voluntary_exits,
      attestations: block.body.attestations
    }

    filter_messages(block.slot, operations)
  end

  def init() do
    topics = topics()
    Enum.each(topics, &Libp2pPort.join_topic/1)
    store_slot(nil)
    Enum.each(@operations, fn operation -> store_operation(operation, []) end)
  end

  defp get_operation({:get, operation, count}) when operation in @operations do
    # NOTE: we don't remove these from the db, since after a block is built
    #  :new_block will be called, and already added messages will be removed

    slot = fetch_slot!()

    operations =
      fetch_operation!(operation) |> Stream.reject(&ignore?(&1, slot)) |> Enum.take(count)

    operations
  end

  @impl true
  def handle_gossip_message(
        <<_::binary-size(15)>> <> "beacon_aggregate_and_proof" <> _,
        _msg_id,
        message
      ) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok,
          %Types.SignedAggregateAndProof{message: %Types.AggregateAndProof{aggregate: aggregate}}} <-
           Ssz.from_ssz(uncompressed, Types.SignedAggregateAndProof) do
      votes = BitField.count(aggregate.aggregation_bits)
      slot = aggregate.data.slot
      root = aggregate.data.beacon_block_root |> Base.encode16()

      Logger.debug(
        "[Gossip] Aggregate decoded. Total attestations: #{votes}",
        slot: slot,
        root: root
      )

      # We are getting ~500 attestations in half a second. This is overwhelming the store GenServer at the moment.
      # ForkChoice.on_attestation(aggregate)
      handle_msg({:attestation, aggregate})
    end
  end

  @impl true
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

  @impl true
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

  @impl true
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

  @impl true
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

  defp topics() do
    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)

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

  defp filter_messages(slot, operations) do
    indices =
      operations.bls_to_execution_changes
      |> MapSet.new(& &1.message.validator_index)

    fetch_operation!(:bls_to_execution_change)
    |> Enum.reject(&MapSet.member?(indices, &1.message.validator_index))
    |> then(&store_operation(:bls_to_execution_change, &1))

    # TODO: improve AttesterSlashing filtering
    fetch_operation!(:attester_slashing)
    |> Enum.reject(&Enum.member?(operations.attester_slashings, &1))
    |> then(&store_operation(:attester_slashing, &1))

    slashed_proposers =
      operations.proposer_slashings |> MapSet.new(& &1.signed_header_1.message.proposer_index)

    fetch_operation!(:proposer_slashing)
    |> Enum.reject(&MapSet.member?(slashed_proposers, &1.signed_header_1.message.proposer_index))
    |> then(&store_operation(:proposer_slashing, &1))

    exited = operations.voluntary_exits |> MapSet.new(& &1.message.validator_index)

    fetch_operation!(:voluntary_exit)
    |> Enum.reject(&MapSet.member?(exited, &1.message.validator_index))
    |> then(&store_operation(:voluntary_exit, &1))

    # TODO: improve attestation filtering
    added_attestations = MapSet.new(operations.attestations)

    fetch_operation!(:attestation)
    |> Stream.reject(&MapSet.member?(added_attestations, &1))
    |> Enum.reject(&old_attestation?(&1, slot))
    |> then(&store_operation(:attestation, &1))

    store_slot(slot)
  end

  defp old_attestation?(%Attestation{data: data}, slot) do
    current_epoch = Misc.compute_epoch_at_slot(slot + 1)
    data.target.epoch not in [current_epoch, current_epoch - 1]
  end

  defp ignore?(%Attestation{}, nil), do: false

  defp ignore?(%Attestation{data: data}, slot) do
    data.slot + ChainSpec.get("MIN_ATTESTATION_INCLUSION_DELAY") > slot
  end

  defp ignore?(_, _), do: false

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
