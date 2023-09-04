defmodule LambdaEthereumConsensus.GossipSub do
  @moduledoc """
  Supervises topic subscribers.
  """
  use Supervisor

  alias LambdaEthereumConsensus.GossipConsumer

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(gsub) do
    topics = [
      {"beacon_block", SszTypes.SignedBeaconBlock},
      {"beacon_aggregate_and_proof", SszTypes.SignedBeaconBlockHeader},
      {"beacon_attestation_0", SszTypes.Attestation},
      {"voluntary_exit", SszTypes.SignedVoluntaryExit},
      {"proposer_slashing", SszTypes.ProposerSlashing},
      {"attester_slashing", SszTypes.AttesterSlashing},
      {"sync_committee_contribution_and_proof", SszTypes.SignedBeaconBlockHeader},
      {"sync_committee_0", SszTypes.SignedBeaconBlockHeader},
      {"bls_to_execution_change", SszTypes.SignedBeaconBlockHeader}
    ]

    children =
      for {topic_msg, payload} <- topics do
        topic = "/eth2/bba4da96/#{topic_msg}/ssz_snappy"
        {GossipConsumer, %{gsub: gsub, topic: topic, payload: payload}}
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
