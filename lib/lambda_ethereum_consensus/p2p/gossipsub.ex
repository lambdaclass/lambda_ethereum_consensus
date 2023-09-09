defmodule LambdaEthereumConsensus.P2P.GossipSub do
  @moduledoc """
  Supervises topic subscribers.
  """
  use Supervisor

  alias LambdaEthereumConsensus.P2P.GossipConsumer
  alias LambdaEthereumConsensus.P2P.GossipHandler

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init([gsub]) do
    topics = [
      {"beacon_block", SszTypes.SignedBeaconBlock},
      {"beacon_attestation_0", SszTypes.Attestation},
      {"voluntary_exit", SszTypes.SignedVoluntaryExit},
      {"proposer_slashing", SszTypes.ProposerSlashing},
      {"attester_slashing", SszTypes.AttesterSlashing},
      {"bls_to_execution_change", SszTypes.SignedBLSToExecutionChange},
      # use type SignedAggregateAndProof
      {"beacon_aggregate_and_proof", SszTypes.SignedBeaconBlockHeader},
      # use type SignedContributionAndProof
      {"sync_committee_contribution_and_proof", SszTypes.SignedBeaconBlockHeader},
      # use type SyncCommitteeMessage
      {"sync_committee_0", SszTypes.SignedBeaconBlockHeader}
    ]

    children =
      for {topic_msg, ssz_type} <- topics do
        topic = "/eth2/bba4da96/#{topic_msg}/ssz_snappy"
        {GossipConsumer, %{gsub: gsub, topic: topic, ssz_type: ssz_type, handler: GossipHandler}}
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
