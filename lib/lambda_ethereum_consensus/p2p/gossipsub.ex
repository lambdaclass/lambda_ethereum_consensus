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
  def init(_init_arg) do
    topics = [
      "beacon_block",
      "beacon_aggregate_and_proof",
      "beacon_attestation_0",
      "voluntary_exit",
      # "proposer_slashing",
      # "attester_slashing",
      "sync_committee_contribution_and_proof",
      "sync_committee_0",
      "bls_to_execution_change"
    ]

    children =
      for topic_msg <- topics do
        topic = "/eth2/bba4da96/#{topic_msg}/ssz_snappy"
        {GossipConsumer, %{topic: topic}}
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
