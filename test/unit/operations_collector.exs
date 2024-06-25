defmodule Unit.OperationsCollectorTest do
  alias Fixtures.Block
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
    OperationsCollector.init()
    :ok
  end

  defp checkpoint() do
    %Types.Checkpoint{
      epoch: Random.uint64(),
      root: Random.binary(32)
    }
  end

  defp attestation() do
    checkpoint_source = checkpoint()
    checkpoint_target = checkpoint()

    attestation_data = %Types.AttestationData{
      slot: Random.uint64(),
      index: Random.uint64(),
      beacon_block_root: Random.binary(32),
      source: checkpoint_source,
      target: checkpoint_target
    }

    %Types.Attestation{
      data: attestation_data,
      aggregation_bits: <<>>,
      signature: Random.bls_signature()
    }
  end

  defp signed_voluntary_exit() do
    voluntary_exit = %Types.VoluntaryExit{
      epoch: Random.uint64(),
      validator_index: Random.uint64()
    }

    %Types.SignedVoluntaryExit{
      message: voluntary_exit,
      signature: Random.bls_signature()
    }
  end

  defp compress(data) do
    {:ok, encoded} = SszEx.encode(data)
    {:ok, compressed} = :snappyer.compress(encoded)
    compressed
  end

  defp send_attestation(attestation) do
    aggregate_and_proof = %Types.AggregateAndProof{
      aggregator_index: Random.uint64(),
      aggregate: attestation,
      selection_proof: Random.bls_signature()
    }

    signed_aggregate_and_proof = %Types.SignedAggregateAndProof{
      message: aggregate_and_proof,
      signature: Random.bls_signature()
    }

    compressed_attestation = compress(signed_aggregate_and_proof)
    topic = <<0::size(120), "beacon_aggregate_and_proof">>

    OperationsCollector.handle_gossip_message(topic, "msg_id", compressed_attestation)
  end

  defp send_voluntary_exit(signed_voluntary_exit) do
    compressed = compress(signed_voluntary_exit)
    topic = <<0::size(120), "voluntary_exit">>

    OperationsCollector.handle_gossip_message(topic, "msg_id", compressed)
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
    send_attestation(expected_attestation)

    assert OperationsCollector.get_attestations(5) == [expected_attestation]
  end

  @tag :tmp_dir
  test "add voluntary exit" do
    signed_voluntary_exit = signed_voluntary_exit()
    send_voluntary_exit(signed_voluntary_exit)

    assert OperationsCollector.get_voluntary_exits(5) == [signed_voluntary_exit]
  end

  @tag :tmp_dir
  test "add two attestations" do
    attestation1 = attestation()
    attestation2 = attestation()
    send_attestation(attestation1)
    send_attestation(attestation2)

    assert OperationsCollector.get_attestations(5) == [attestation2, attestation1]
  end

  @tag :tmp_dir
  test "add two different operations" do
    attestation = attestation()
    signed_voluntary_exit = signed_voluntary_exit()

    send_voluntary_exit(signed_voluntary_exit)
    send_attestation(attestation)

    assert OperationsCollector.get_attestations(5) == [attestation]
    assert OperationsCollector.get_voluntary_exits(5) == [signed_voluntary_exit]
  end

  @tag :tmp_dir
  test "filter zero operations" do
    # send voluntary exit
    signed_voluntary_exit = signed_voluntary_exit()
    send_voluntary_exit(signed_voluntary_exit)
    # send attestation
    attestation = attestation()
    send_attestation(attestation)

    operations = %{
      bls_to_execution_changes: [],
      attester_slashings: [],
      proposer_slashings: [],
      voluntary_exits: [],
      attestations: []
    }

    block = Block.beacon_block()
    block = %{block | body: Map.merge(block.body, operations)}

    # ensure that the attestation is not considered old.
    new_block_slot = attestation.data.target.epoch * ChainSpec.get("SLOTS_PER_EPOCH")
    block = %{block | slot: new_block_slot}

    OperationsCollector.notify_new_block(block)
    assert OperationsCollector.get_voluntary_exits(5) == [signed_voluntary_exit]
    assert OperationsCollector.get_attestations(5) == [attestation]
  end

  @tag :tmp_dir
  test "filter included operations" do
    # send voluntary exit
    signed_voluntary_exit = signed_voluntary_exit()
    send_voluntary_exit(signed_voluntary_exit)
    # send attestation
    attestation = attestation()
    send_attestation(attestation)

    # filter messages
    operations = %{
      bls_to_execution_changes: [],
      attester_slashings: [],
      proposer_slashings: [],
      voluntary_exits: [signed_voluntary_exit],
      attestations: [attestation]
    }

    block = Block.beacon_block()
    block = %{block | body: Map.merge(block.body, operations)}

    # ensure that the attestation is not considered old.
    new_block_slot = attestation.data.target.epoch * ChainSpec.get("SLOTS_PER_EPOCH")
    block = %{block | slot: new_block_slot}

    OperationsCollector.notify_new_block(block)
    assert OperationsCollector.get_voluntary_exits(5) == []
    assert OperationsCollector.get_attestations(5) == []
  end

  @tag :tmp_dir
  test "filter old attestation" do
    # send attestation
    attestation = attestation()
    send_attestation(attestation)

    operations = %{
      bls_to_execution_changes: [],
      attester_slashings: [],
      proposer_slashings: [],
      voluntary_exits: [],
      attestations: []
    }

    block = Block.beacon_block()
    block = %{block | body: Map.merge(block.body, operations)}

    # filter old attestation
    new_block_slot = (attestation.data.target.epoch + 2) * ChainSpec.get("SLOTS_PER_EPOCH")
    block = %{block | slot: new_block_slot}

    OperationsCollector.notify_new_block(block)

    assert OperationsCollector.get_attestations(5) == []
  end

  @tag :tmp_dir
  test "ignore future attestations" do
    attestation = attestation()

    # set target epoch properly
    target_epoch = div(attestation.data.slot, ChainSpec.get("SLOTS_PER_EPOCH"))

    attestation = %{
      attestation
      | data: %{
          attestation.data
          | target: %{attestation.data.target | epoch: target_epoch}
        }
    }

    # set the OperationsCollector slot
    operations = %{
      bls_to_execution_changes: [],
      attester_slashings: [],
      proposer_slashings: [],
      voluntary_exits: [],
      attestations: []
    }

    block = Block.beacon_block()
    block = %{block | body: Map.merge(block.body, operations)}
    block = %{block | slot: attestation.data.slot}

    OperationsCollector.notify_new_block(block)

    # send future attestation
    send_attestation(attestation)

    # attestation is ignored.
    assert OperationsCollector.get_attestations(5) == []

    # increment the OperationsCollector slot
    block = %{block | slot: block.slot + 1}

    OperationsCollector.notify_new_block(block)

    assert OperationsCollector.get_attestations(5) == [attestation]
  end
end
