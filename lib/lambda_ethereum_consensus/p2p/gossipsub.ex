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
      # use type SignedBeaconBlock
      {"beacon_block", SszTypes.SignedBeaconBlockHeader},
      # use type SignedAggregateAndProof
      {"beacon_aggregate_and_proof", SszTypes.SignedBeaconBlockHeader},
      {"beacon_attestation_0", SszTypes.Attestation},
      {"voluntary_exit", SszTypes.SignedVoluntaryExit},
      {"proposer_slashing", SszTypes.ProposerSlashing},
      {"attester_slashing", SszTypes.AttesterSlashing},
      # use type SignedContributionAndProof
      {"sync_committee_contribution_and_proof", SszTypes.SignedBeaconBlockHeader},
      # use type SyncCommitteeMessage
      {"sync_committee_0", SszTypes.SignedBeaconBlockHeader},
      {"bls_to_execution_change", SszTypes.SignedBLSToExecutionChange}
    ]

    children =
      for {topic_msg, type} <- topics do
        topic = "/eth2/bba4da96/#{topic_msg}/ssz_snappy"
        {GossipConsumer, %{gsub: gsub, topic: topic, type: type, handler: GossipHandler}}
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
