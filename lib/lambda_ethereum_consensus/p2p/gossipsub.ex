defmodule LambdaEthereumConsensus.P2P.GossipSub do
  @moduledoc """
  Supervises topic subscribers.
  """
  use Supervisor

  alias LambdaEthereumConsensus.P2P.GossipConsumer
  alias LambdaEthereumConsensus.P2P.GossipHandler

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    topics = [
      {"beacon_block", Types.SignedBeaconBlock},
      {"beacon_aggregate_and_proof", Types.SignedAggregateAndProof}
      # {"beacon_attestation_0", Types.Attestation},
      # {"voluntary_exit", Types.SignedVoluntaryExit},
      # {"proposer_slashing", Types.ProposerSlashing},
      # {"attester_slashing", Types.AttesterSlashing},
      # {"bls_to_execution_change", Types.SignedBLSToExecutionChange},
      # {"sync_committee_contribution_and_proof", Types.SignedContributionAndProof},
      # {"sync_committee_0", Types.SyncCommitteeMessage}
    ]

    children =
      for {topic_msg, ssz_type} <- topics do
        topic = "/eth2/bba4da96/#{topic_msg}/ssz_snappy"
        {GossipConsumer, %{topic: topic, ssz_type: ssz_type, handler: GossipHandler}}
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
