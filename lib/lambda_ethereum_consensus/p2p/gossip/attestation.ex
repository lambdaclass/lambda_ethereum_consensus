defmodule LambdaEthereumConsensus.P2P.Gossip.Attestation do
  @moduledoc """
  This module handles attestation gossipsub topics.
  """
  use GenServer

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias LambdaEthereumConsensus.StateTransition.Misc

  @behaviour Handler

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @spec join(non_neg_integer()) :: :ok
  def join(subnet_id) do
    topic = get_topic_name(subnet_id)
    Libp2pPort.join_topic(topic)
    P2P.Metadata.set_attnet(subnet_id)
    # NOTE: this depends on the metadata being updated
    update_enr()
  end

  @impl true
  def handle_gossip_message(topic, msg_id, message) do
    send(__MODULE__, {:gossipsub, {topic, msg_id, message}})
  end

  @spec leave(non_neg_integer()) :: :ok
  def leave(subnet_id) do
    topic = get_topic_name(subnet_id)
    Libp2pPort.leave_topic(topic)
    P2P.Metadata.clear_attnet(subnet_id)
    # NOTE: this depends on the metadata being updated
    update_enr()
  end

  @spec publish(non_neg_integer(), Types.Attestation.t()) :: :ok
  def publish(subnet_id, %Types.Attestation{} = attestation) do
    topic = get_topic_name(subnet_id)
    {:ok, encoded} = SszEx.encode(attestation, Types.Attestation)
    {:ok, message} = :snappyer.compress(encoded)
    Libp2pPort.publish(topic, message)
  end

  def publish_aggregate(%Types.SignedAggregateAndProof{} = signed_aggregate) do
    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)
    topic = "/eth2/#{fork_context}/beacon_aggregate_and_proof/ssz_snappy"
    {:ok, encoded} = SszEx.encode(signed_aggregate, Types.SignedAggregateAndProof)
    {:ok, message} = :snappyer.compress(encoded)
    Libp2pPort.publish(topic, message)
  end

  @spec collect(non_neg_integer(), Types.Attestation.t()) :: :ok
  def collect(subnet_id, attestation) do
    GenServer.call(__MODULE__, {:collect, subnet_id, attestation})
    join(subnet_id)
  end

  @spec stop_collecting(non_neg_integer()) ::
          {:ok, list(Types.Attestation.t())} | {:error, String.t()}
  def stop_collecting(subnet_id) do
    # TODO: implement some way to unsubscribe without leaving the topic
    topic = get_topic_name(subnet_id)
    Libp2pPort.leave_topic(topic)
    Libp2pPort.join_topic(topic)
    GenServer.call(__MODULE__, {:stop_collecting, subnet_id})
  end

  defp get_topic_name(subnet_id) do
    # TODO: this doesn't take into account fork digest changes
    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)
    "/eth2/#{fork_context}/beacon_attestation_#{subnet_id}/ssz_snappy"
  end

  defp update_enr() do
    enr_fork_id = compute_enr_fork_id()
    %{attnets: attnets, syncnets: syncnets} = P2P.Metadata.get_metadata()
    Libp2pPort.update_enr(enr_fork_id, attnets, syncnets)
  end

  defp compute_enr_fork_id() do
    current_version = BeaconChain.get_fork_version()

    fork_digest =
      Misc.compute_fork_digest(current_version, ChainSpec.get_genesis_validators_root())

    %Types.EnrForkId{
      fork_digest: fork_digest,
      next_fork_version: current_version,
      next_fork_epoch: Constants.far_future_epoch()
    }
  end

  @impl true
  def init(_init_arg) do
    {:ok, %{attnets: %{}, attestations: %{}}}
  end

  @impl true
  def handle_call({:collect, subnet_id, attestation}, _from, state) do
    attestations = Map.put(state.attestations, subnet_id, [attestation])
    attnets = Map.put(state.attnets, subnet_id, attestation.data)
    new_state = %{state | attnets: attnets, attestations: attestations}
    get_topic_name(subnet_id) |> Libp2pPort.subscribe_to_topic(__MODULE__)
    {:reply, :ok, new_state}
  end

  def handle_call({:stop_collecting, subnet_id}, _from, state) do
    if Map.has_key?(state.attnets, subnet_id) do
      {collected, atts} = Map.pop(state.attestations, subnet_id, [])
      new_state = %{state | attnets: Map.delete(state.attnets, subnet_id), attestations: atts}
      {:reply, {:ok, collected}, new_state}
    else
      {:reply, {:error, "subnet not joined"}, state}
    end
  end

  @impl true
  def handle_info({:gossipsub, {topic, msg_id, message}}, state) do
    subnet_id = extract_subnet_id(topic)

    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, attestation} <- Ssz.from_ssz(uncompressed, Types.Attestation) do
      # TODO: validate before accepting
      Libp2pPort.validate_message(msg_id, :accept)
      new_state = store_attestation(subnet_id, state, attestation)
      {:noreply, new_state}
    else
      {:error, _} -> Libp2pPort.validate_message(msg_id, :reject)
    end
  end

  @subnet_id_start byte_size("/eth2/00000000/beacon_attestation_")

  defp extract_subnet_id(<<_::binary-size(@subnet_id_start)>> <> id_with_trailer) do
    id_with_trailer |> String.trim_trailing("/ssz_snappy") |> String.to_integer()
  end

  defp store_attestation(subnet_id, %{attestations: attestations} = state, attestation) do
    case Map.get(attestation, subnet_id) do
      data when data !== attestation.data ->
        state

      _ ->
        attestations = Map.update(attestations, subnet_id, [], &[attestation | &1])
        %{state | attestations: attestations}
    end
  end
end
