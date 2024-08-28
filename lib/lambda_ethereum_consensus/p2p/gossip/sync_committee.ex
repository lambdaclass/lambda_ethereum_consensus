defmodule LambdaEthereumConsensus.P2P.Gossip.SyncCommittee do
  @moduledoc """
  This module handles sync committee from specific gossip subnets.
  Used by validators to fulfill aggregation duties.

  TODO: THIS IS EXACTLY THE SAME AS ATTSUBNET. ALSO NEEDS TESTS
  """
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.SyncSubnetInfo

  @behaviour Handler

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

  @impl true
  def handle_gossip_message(store, topic, msg_id, message) do
    handle_gossip_message(topic, msg_id, message)
    store
  end

  def handle_gossip_message(topic, msg_id, message) do
    subnet_id = extract_subnet_id(topic)

    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, sync_committee_msg} <- Ssz.from_ssz(uncompressed, Types.SyncCommitteeMessage) do
      # TODO: validate before accepting
      Libp2pPort.validate_message(msg_id, :accept)

      SyncSubnetInfo.add_message!(subnet_id, sync_committee_msg)
    else
      {:error, _} -> Libp2pPort.validate_message(msg_id, :reject)
    end
  end

  @spec publish(Types.SyncCommitteeMessage.t(), [non_neg_integer()]) :: :ok
  def publish(%Types.SyncCommitteeMessage{} = sync_committee_msg, subnet_ids) do
    for subnet_id <- subnet_ids do
      topic = topic(subnet_id)

      {:ok, encoded} = SszEx.encode(sync_committee_msg, Types.SyncCommitteeMessage)
      {:ok, message} = :snappyer.compress(encoded)
      Libp2pPort.publish(topic, message)
    end

    :ok
  end

  @spec collect([non_neg_integer()], Types.SyncCommitteeMessage.t()) :: :ok
  def collect(subnet_ids, message) do
    join(subnet_ids)

    for subnet_id <- subnet_ids do
      SyncSubnetInfo.new_subnet_with_message(subnet_id, message)
      Libp2pPort.async_subscribe_to_topic(topic(subnet_id), __MODULE__)
    end

    :ok
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

  @subnet_id_start byte_size("/eth2/00000000/sync_committee_")

  defp extract_subnet_id(<<_::binary-size(@subnet_id_start)>> <> id_with_trailer) do
    id_with_trailer |> String.trim_trailing("/ssz_snappy") |> String.to_integer()
  end
end
