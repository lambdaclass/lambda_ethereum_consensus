defmodule LambdaEthereumConsensus.P2P.GossipSub do
  @moduledoc """
  Supervises topic subscribers.
  """
  use Supervisor

  alias LambdaEthereumConsensus.P2P.Gossip.Consumer
  alias LambdaEthereumConsensus.P2P.Gossip.Handler

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init([fork_digest_context]) do
    topics = [
      {"beacon_block", Types.SignedBeaconBlock, &Handler.handle_beacon_block/1},
      {"beacon_aggregate_and_proof", Types.SignedAggregateAndProof,
       &Handler.handle_beacon_aggregate_and_proof/1}
      # {"beacon_attestation_0", Types.Attestation},
      # {"voluntary_exit", Types.SignedVoluntaryExit},
      # {"proposer_slashing", Types.ProposerSlashing},
      # {"attester_slashing", Types.AttesterSlashing},
      # {"bls_to_execution_change", Types.SignedBLSToExecutionChange},
      # {"sync_committee_contribution_and_proof", Types.SignedContributionAndProof},
      # {"sync_committee_0", Types.SyncCommitteeMessage}
    ]

    children =
      for {topic_msg, ssz_type, handler} <- topics do
        topic = "/eth2/#{fork_digest_context}/#{topic_msg}/ssz_snappy"
        {Consumer, %{topic: topic, ssz_type: ssz_type, handler: handler}}
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
