defmodule LambdaEthereumConsensus.P2P.GossipSub do
  @moduledoc """
  Supervises topic subscribers.
  """
  use Supervisor

  alias LambdaEthereumConsensus.Handlers
  alias LambdaEthereumConsensus.P2P.GossipConsumer

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init([gsub]) do
    topics = [
      {"beacon_block", SszTypes.SignedBeaconBlock, Handlers.BlockHandler}
      # {"beacon_attestation_0", SszTypes.Attestation, Handlers.GenericHandler},
      # {"voluntary_exit", SszTypes.SignedVoluntaryExit, Handlers.GenericHandler},
      # {"proposer_slashing", SszTypes.ProposerSlashing, Handlers.GenericHandler},
      # {"attester_slashing", SszTypes.AttesterSlashing, Handlers.GenericHandler},
      # {"bls_to_execution_change", SszTypes.SignedBLSToExecutionChange, Handlers.GenericHandler},
      # {"beacon_aggregate_and_proof", SszTypes.SignedAggregateAndProof, Handlers.GenericHandler}
      # {"sync_committee_contribution_and_proof", SszTypes.SignedContributionAndProof},
      # {"sync_committee_0", SszTypes.SyncCommitteeMessage}
    ]

    children =
      for {topic_msg, ssz_type, handler} <- topics do
        topic = "/eth2/bba4da96/#{topic_msg}/ssz_snappy"
        {GossipConsumer, %{gsub: gsub, topic: topic, ssz_type: ssz_type, handler: handler}}
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
