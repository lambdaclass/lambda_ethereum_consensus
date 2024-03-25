defmodule LambdaEthereumConsensus.P2P.GossipSub do
  @moduledoc """
  Supervises topic subscribers.
  """
  use Supervisor

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.P2P.Gossip.Consumer
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias Types.SignedBeaconBlock

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    topics = [
      {"beacon_block", SignedBeaconBlock, &Handler.handle_beacon_block/1},
      {"beacon_aggregate_and_proof", Types.SignedAggregateAndProof,
       &Handler.handle_beacon_aggregate_and_proof/1},
      # {"voluntary_exit", Types.SignedVoluntaryExit},
      {"proposer_slashing", Types.ProposerSlashing, &Handler.handle_proposer_slashing/1},
      {"attester_slashing", Types.AttesterSlashing, &Handler.handle_attester_slashing/1},
      {"bls_to_execution_change", Types.SignedBLSToExecutionChange,
       &Handler.handle_bls_to_execution_change/1}
      # {"sync_committee_contribution_and_proof", Types.SignedContributionAndProof},
      # {"sync_committee_0", Types.SyncCommitteeMessage}
    ]

    # Add blob sidecar topics
    # NOTE: there's one per blob index in Deneb (6 blobs per block)
    topics =
      topics ++
        Enum.map(0..5, fn i ->
          {"blob_sidecar_#{i}", Types.BlobSidecar, &Handler.handle_blob_sidecar(&1, i)}
        end)

    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)

    children =
      for {topic_msg, ssz_type, handler} <- topics do
        topic = "/eth2/#{fork_context}/#{topic_msg}/ssz_snappy"
        {Consumer, %{topic: topic, ssz_type: ssz_type, handler: handler}}
      end

    children = children ++ [LambdaEthereumConsensus.P2P.Gossip.OperationsCollector]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
