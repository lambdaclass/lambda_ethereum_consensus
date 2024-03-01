defmodule LambdaEthereumConsensus.P2P.Gossip.Attestation do
  @moduledoc """
  This module handles attestation gossipsub topics.
  """
  use GenServer

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P

  @subnet_id_start byte_size("/eth2/00000000/beacon_attestation_")
  @subnet_id_end byte_size("/ssz_snappy")

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def join(subnet_id) do
    topic = get_topic_name(subnet_id)
    Libp2pPort.join_topic(topic)
    P2P.Metadata.set_attestation_subnet(subnet_id, true)
  end

  def leave(subnet_id) do
    topic = get_topic_name(subnet_id)
    Libp2pPort.leave_topic(topic)
    P2P.Metadata.set_attestation_subnet(subnet_id, false)
  end

  def collect(subnet_id), do: GenServer.call(__MODULE__, {:collect, subnet_id})
  def stop_collecting(subnet_id), do: GenServer.call(__MODULE__, {:stop_collecting, subnet_id})

  @impl true
  def init(_init_arg) do
    {:ok, %{attnets: MapSet.new(), attestations: %{}}}
  end

  @impl true
  def handle_call({:collect, subnet_id}, _from, state) do
    :ok = get_topic_name(subnet_id) |> Libp2pPort.subscribe_to_topic()
    new_state = %{state | attnets: MapSet.put(state.attnets, subnet_id)}
    {:reply, :ok, new_state}
  end

  def handle_call({:stop_collecting, subnet_id}, _from, state) do
    if MapSet.member?(state.attnets, subnet_id) do
      :ok = get_topic_name(subnet_id) |> Libp2pPort.leave_topic()
      {collected, atts} = Map.pop(state.attestations, subnet_id, [])
      new_state = %{state | attnets: MapSet.delete(state.attnets, subnet_id), attestations: atts}
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
      # TODO: validate before responding
      Libp2pPort.validate_message(msg_id, :accept)
      new_state = store_attestation(subnet_id, state, attestation)
      {:noreply, new_state}
    else
      {:error, _} -> Libp2pPort.validate_message(msg_id, :reject)
    end
  end

  defp extract_subnet_id(topic) do
    String.slice(topic, @subnet_id_start..-(@subnet_id_end + 1)) |> String.to_integer()
  end

  defp get_topic_name(subnet_id) do
    # TODO: this doesn't take into account fork digest changes
    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)
    "/eth2/#{fork_context}/beacon_attestation_#{subnet_id}/ssz_snappy"
  end

  defp store_attestation(subnet_id, %{attestations: attestations} = state, attestation) do
    attestations = Map.update(attestations, subnet_id, [], &[attestation | &1])
    %{state | attestations: attestations}
  end
end
