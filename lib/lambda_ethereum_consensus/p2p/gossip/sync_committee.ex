defmodule LambdaEthereumConsensus.P2P.Gossip.SyncCommittee do
  @moduledoc """
  This module handles sync committee from specific gossip subnets.
  Used by validators to fulfill aggregation duties.
  """
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Libp2pPort

  require Logger

  @spec join([non_neg_integer()]) :: :ok
  def join(subnet_ids) when is_list(subnet_ids) do
    for subnet_id <- subnet_ids do
      topic = topic(subnet_id)
      Libp2pPort.join_topic(topic)

      P2P.Metadata.set_syncnet(subnet_id)
    end

    P2P.Metadata.get_metadata()
    |> update_enr()
  end

  @spec publish(Types.SyncCommitteeMessage.t(), [non_neg_integer()]) :: :ok
  def publish(%Types.SyncCommitteeMessage{} = sync_committee_msg, subnet_ids) do
    for subnet_id <- subnet_ids do
      topic = topic(subnet_id)

      {:ok, encoded} = SszEx.encode(sync_committee_msg, Types.SyncCommitteeMessage)
      {:ok, message} = :snappyer.compress(encoded)
      Libp2pPort.publish(topic, message)
    end
  end

  @spec collect(non_neg_integer(), Types.SyncCommitteeMessage.t()) :: :ok
  def collect(subnet_id, _messages) do
    join(subnet_id)
    #SubnetInfo.new_subnet_with_attestation(subnet_id, attestation)
    Libp2pPort.async_subscribe_to_topic(topic(subnet_id), __MODULE__)
  end

  defp topic(subnet_id) do
    # TODO: this doesn't take into account fork digest changes
    fork_context = ForkChoice.get_fork_digest() |> Base.encode16(case: :lower)
    "/eth2/#{fork_context}/sync_committee_#{subnet_id}/ssz_snappy"
  end

  defp update_enr(%{attnets: attnets, syncnets: syncnets}) do
    enr_fork_id = compute_enr_fork_id()
    Libp2pPort.update_enr(enr_fork_id, attnets, syncnets)
  end

  defp compute_enr_fork_id() do
    current_version = ForkChoice.get_fork_version()

    fork_digest =
      Misc.compute_fork_digest(current_version, ChainSpec.get_genesis_validators_root())

    %Types.EnrForkId{
      fork_digest: fork_digest,
      next_fork_version: current_version,
      next_fork_epoch: Constants.far_future_epoch()
    }
  end
end
