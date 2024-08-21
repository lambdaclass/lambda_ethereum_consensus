defmodule LambdaEthereumConsensus.P2P.Gossip.SyncCommittee do
  @moduledoc """
  This module handles sync committee from specific gossip subnets.
  Used by validators to fulfill aggregation duties.
  """
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Libp2pPort

  require Logger

  @spec publish(Types.SyncCommitteeMessage.t(), [non_neg_integer()]) :: :ok
  def publish(%Types.SyncCommitteeMessage{} = sync_committee_msg, subnet_ids) do
    Enum.each(subnet_ids, fn subnet_id ->
      topic = topic(subnet_id)

      {:ok, encoded} = SszEx.encode(sync_committee_msg, Types.SyncCommitteeMessage)
      {:ok, message} = :snappyer.compress(encoded)
      Libp2pPort.publish(topic, message)
    end)
  end

  defp topic(subnet_id) do
    # TODO: this doesn't take into account fork digest changes
    fork_context = ForkChoice.get_fork_digest() |> Base.encode16(case: :lower)
    "/eth2/#{fork_context}/sync_committee_#{subnet_id}/ssz_snappy"
  end
end
