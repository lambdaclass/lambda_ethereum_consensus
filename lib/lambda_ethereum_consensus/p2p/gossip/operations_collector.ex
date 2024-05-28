defmodule LambdaEthereumConsensus.P2P.Gossip.OperationsCollector do
  @moduledoc """
  Module that stores the operations received from gossipsub.
  """
  use GenServer

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Utils.BitField
  alias Types.Attestation
  alias Types.AttesterSlashing
  alias Types.BeaconBlock
  alias Types.ProposerSlashing
  alias Types.SignedBLSToExecutionChange
  alias Types.SignedVoluntaryExit

  require Logger

  @behaviour Handler

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

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def start() do
    GenServer.call(__MODULE__, :start)
  end

  @spec get_bls_to_execution_changes(non_neg_integer()) :: list(SignedBLSToExecutionChange.t())
  def get_bls_to_execution_changes(count) do
    GenServer.call(__MODULE__, {:get, :bls_to_execution_change, count})
  end

  @spec get_attester_slashings(non_neg_integer()) :: list(AttesterSlashing.t())
  def get_attester_slashings(count) do
    GenServer.call(__MODULE__, {:get, :attester_slashing, count})
  end

  @spec get_proposer_slashings(non_neg_integer()) :: list(ProposerSlashing.t())
  def get_proposer_slashings(count) do
    GenServer.call(__MODULE__, {:get, :proposer_slashing, count})
  end

  @spec get_voluntary_exits(non_neg_integer()) :: list(SignedVoluntaryExit.t())
  def get_voluntary_exits(count) do
    GenServer.call(__MODULE__, {:get, :voluntary_exit, count})
  end

  @spec get_attestations(non_neg_integer()) :: list(Attestation.t())
  def get_attestations(count) do
    GenServer.call(__MODULE__, {:get, :attestation, count})
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

    GenServer.cast(__MODULE__, {:new_block, block.slot, operations})
  end

  @impl true
  def handle_gossip_message(topic, msg_id, message) do
    GenServer.cast(__MODULE__, {:gossipsub, {topic, msg_id, message}})
  end

  @impl GenServer
  def init(_init_arg) do
    topics = get_topic_names()
    Enum.each(topics, &Libp2pPort.join_topic/1)

    state = Map.new(@operations, &{&1, []}) |> Map.put(:slot, nil) |> Map.put(:topics, topics)
    {:ok, state}
  end

  @impl true
  def handle_call(:start, _from, %{topics: topics} = state) do
    Enum.each(topics, fn topic -> Libp2pPort.subscribe_to_topic(topic, __MODULE__) end)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:get, operation, count}, _from, state) when operation in @operations do
    # NOTE: we don't remove these from the state, since after a block is built
    #  :new_block will be called, and already added messages will be removed
    operations =
      Map.fetch!(state, operation) |> Stream.filter(&ignore?(&1, state)) |> Enum.take(count)

    {:reply, operations, state}
  end

  @impl GenServer
  def handle_cast({:new_block, slot, operations}, state) do
    {:noreply, filter_messages(state, slot, operations)}
  end

  @impl true
  def handle_cast(
        {:gossipsub,
         {<<_::binary-size(15)>> <> "beacon_aggregate_and_proof" <> _, _msg_id, message}},
        state
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
      handle_msg({:attestation, aggregate}, state)
    end
  end

  @impl true
  def handle_info(
        {:gossipsub, {<<_::binary-size(15)>> <> "voluntary_exit" <> _, _msg_id, message}},
        state
      ) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.SignedVoluntaryExit{} = signed_voluntary_exit} <-
           Ssz.from_ssz(uncompressed, Types.SignedVoluntaryExit) do
      handle_msg({:voluntary_exit, signed_voluntary_exit}, state)
    end
  end

  @impl true
  def handle_info(
        {:gossipsub, {<<_::binary-size(15)>> <> "proposer_slashing" <> _, _msg_id, message}},
        state
      ) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.ProposerSlashing{} = proposer_slashing} <-
           Ssz.from_ssz(uncompressed, Types.ProposerSlashing) do
      handle_msg({:proposer_slashing, proposer_slashing}, state)
    end
  end

  @impl true
  def handle_info(
        {:gossipsub, {<<_::binary-size(15)>> <> "attester_slashing" <> _, _msg_id, message}},
        state
      ) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.AttesterSlashing{} = attester_slashing} <-
           Ssz.from_ssz(uncompressed, Types.AttesterSlashing) do
      handle_msg({:attester_slashing, attester_slashing}, state)
    end
  end

  @impl true
  def handle_info(
        {:gossipsub,
         {<<_::binary-size(15)>> <> "bls_to_execution_change" <> _, _msg_id, message}},
        state
      ) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.SignedBLSToExecutionChange{} = bls_to_execution_change} <-
           Ssz.from_ssz(uncompressed, Types.SignedBLSToExecutionChange) do
      handle_msg({:bls_to_execution_change, bls_to_execution_change}, state)
    end
  end

  defp get_topic_names() do
    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)

    topics =
      Enum.map(@topic_msgs, fn topic_msg ->
        "/eth2/#{fork_context}/#{topic_msg}/ssz_snappy"
      end)

    topics
  end

  # TODO: filter duplicates
  defp handle_msg({operation, msg}, state)
       when operation in @operations do
    new_msgs = [msg | Map.fetch!(state, operation)]
    {:noreply, Map.replace!(state, operation, new_msgs)}
  end

  defp filter_messages(state, slot, operations) do
    indices =
      operations.bls_to_execution_changes
      |> MapSet.new(& &1.message.validator_index)

    bls_to_execution_changes =
      state.bls_to_execution_change
      |> Enum.reject(&MapSet.member?(indices, &1.message.validator_index))

    # TODO: improve AttesterSlashing filtering
    attester_slashings =
      state.attester_slashing |> Enum.reject(&Enum.member?(operations.attester_slashings, &1))

    slashed_proposers =
      operations.proposer_slashings |> MapSet.new(& &1.signed_header_1.message.proposer_index)

    proposer_slashings =
      state.proposer_slashing
      |> Enum.reject(
        &MapSet.member?(slashed_proposers, &1.signed_header_1.message.proposer_index)
      )

    exited = operations.voluntary_exits |> MapSet.new(& &1.message.validator_index)

    voluntary_exits =
      state.voluntary_exit |> Enum.reject(&MapSet.member?(exited, &1.message.validator_index))

    # TODO: improve attestation filtering
    added_attestations = MapSet.new(operations.attestations)

    attestations =
      state.attestation
      |> Stream.reject(&MapSet.member?(added_attestations, &1))
      |> Enum.reject(&old_attestation?(&1, slot))

    %{
      state
      | bls_to_execution_change: bls_to_execution_changes,
        attester_slashing: attester_slashings,
        proposer_slashing: proposer_slashings,
        voluntary_exit: voluntary_exits,
        attestation: attestations,
        slot: slot
    }
  end

  defp old_attestation?(%Attestation{data: data}, slot) do
    current_epoch = Misc.compute_epoch_at_slot(slot + 1)
    data.target.epoch not in [current_epoch, current_epoch - 1]
  end

  defp ignore?(%Attestation{}, %{slot: nil}), do: false

  defp ignore?(%Attestation{data: data}, state) do
    data.slot + ChainSpec.get("MIN_ATTESTATION_INCLUSION_DELAY") > state.slot
  end

  defp ignore?(_, _), do: false
end
