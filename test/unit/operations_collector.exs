defmodule Unit.OperationsCollectorTest do
  alias Fixtures.Random
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.P2P.Gossip.OperationsCollector
  alias LambdaEthereumConsensus.Store.Db

  use ExUnit.Case
  use Patch

  doctest OperationsCollector

  setup %{tmp_dir: tmp_dir} do
    patch(BeaconChain, :get_fork_digest, fn -> "9999" end)
    patch(BeaconChain, :get_fork_version, fn -> "9999" end)
    start_link_supervised!({Db, dir: tmp_dir})
    start_link_supervised!(OperationsCollector)
    :ok
  end

  defp attestation() do
    checkpoint_source = %Types.Checkpoint{
      epoch: 3_776_037_760_046_644_755,
      root:
        <<29, 22, 191, 147, 188, 238, 162, 89, 147, 162, 202, 111, 169, 162, 84, 95, 194, 85, 54,
          172, 44, 74, 37, 128, 248, 21, 86, 246, 151, 54, 24, 54>>
    }

    checkpoint_target = %Types.Checkpoint{
      epoch: 2_840_053_453_521_072_037,
      root:
        <<15, 174, 23, 120, 4, 9, 2, 116, 67, 73, 254, 53, 197, 3, 191, 166, 104, 34, 121, 2, 57,
          69, 75, 69, 254, 237, 132, 68, 254, 49, 127, 175>>
    }

    attestation_data = %Types.AttestationData{
      slot: 5_057_010_135_270_197_978,
      index: 6_920_931_864_607_509_210,
      beacon_block_root:
        <<31, 38, 101, 174, 248, 168, 116, 226, 15, 39, 218, 148, 42, 8, 80, 80, 241, 149, 162,
          32, 176, 208, 120, 120, 89, 123, 136, 115, 154, 28, 21, 174>>,
      source: checkpoint_source,
      target: checkpoint_target
    }

    %Types.Attestation{
      data: attestation_data,
      aggregation_bits: <<>>,
      signature: Random.bls_signature()
    }
  end

  @tag :tmp_dir
  test "init" do
    assert OperationsCollector.get_bls_to_execution_changes(1) == []
    assert OperationsCollector.get_attester_slashings(1) == []
    assert OperationsCollector.get_proposer_slashings(1) == []
    assert OperationsCollector.get_voluntary_exits(1) == []
    assert OperationsCollector.get_attestations(1) == []
  end

  @tag :tmp_dir
  test "add attestation" do
    expected_attestation = attestation()

    aggregate_and_proof = %Types.AggregateAndProof{
      aggregator_index: Random.uint64(),
      aggregate: expected_attestation,
      selection_proof: Random.bls_signature()
    }

    signed_aggregate_and_proof = %Types.SignedAggregateAndProof{
      message: aggregate_and_proof,
      signature: Random.bls_signature()
    }

    {:ok, encoded_attestation} = SszEx.encode(signed_aggregate_and_proof)
    {:ok, compressed_attestation} = :snappyer.compress(encoded_attestation)
    topic = <<0::size(120), "beacon_aggregate_and_proof">>

    OperationsCollector.handle_gossip_message(topic, "msg_id", compressed_attestation)

    assert OperationsCollector.get_attestations(3) == [expected_attestation]
  end
end
