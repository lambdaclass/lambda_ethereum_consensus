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

  def join(subnet_id) do
    topic = get_topic_name(subnet_id)
    # TODO: update ENR
    Libp2pPort.join_topic(topic)
    P2P.Metadata.set_attestation_subnet(subnet_id, true)
  end

  def leave(subnet_id) do
    topic = get_topic_name(subnet_id)
    # TODO: update ENR
    Libp2pPort.leave_topic(topic)
    P2P.Metadata.set_attestation_subnet(subnet_id, false)
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
