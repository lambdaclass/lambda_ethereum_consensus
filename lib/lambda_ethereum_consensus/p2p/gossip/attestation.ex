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
    Libp2pPort.join_topic(topic)
    P2P.Metadata.set_attestation_subnet(subnet_id, true)
    # NOTE: this depends on the metadata being updated
    update_enr()
  end

  def leave(subnet_id) do
    topic = get_topic_name(subnet_id)
    Libp2pPort.leave_topic(topic)
    P2P.Metadata.set_attestation_subnet(subnet_id, false)
    # NOTE: this depends on the metadata being updated
    update_enr()
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

  defp update_enr do
    enr_fork_id = compute_enr_fork_id()
    %{attnets: attnets, syncnets: syncnets} = P2P.Metadata.get_metadata()
    Libp2pPort.update_enr(enr_fork_id, attnets, syncnets)
  end

  defp compute_enr_fork_id do
    current_version = BeaconChain.get_fork_version()

    fork_digest =
      Misc.compute_fork_digest(current_version, ChainSpec.get_genesis_validators_root())

    attnets = ChainSpec.get("ATTESTATION_SUBNET_COUNT") |> BitVector.new()
    syncnets = Constants.sync_committee_subnet_count() |> BitVector.new()

    %EnrForkId{
      fork_digest: fork_digest,
      next_fork_version: current_version,
      next_fork_epoch: Constants.far_future_epoch()
    }
  end
end
