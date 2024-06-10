defmodule Unit.AttestationTest do
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip.Attestation
  alias LambdaEthereumConsensus.P2P.Metadata
  alias LambdaEthereumConsensus.Store.Db
  alias Types.AttestationData
  alias Types.Checkpoint

  use ExUnit.Case
  use Patch

  doctest Attestation

  setup %{tmp_dir: tmp_dir} do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.put(:config, MinimalConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))

    start_link_supervised!({Db, dir: tmp_dir})
    start_link_supervised!(Attestation)
    patch(Libp2pPort, :subscribe_to_topic, fn _, _ -> :ok end)
    patch(Libp2pPort, :join_topic, fn -> :ok end)
    patch(Libp2pPort, :leave_topic, fn -> :ok end)
    patch(Libp2pPort, :update_enr, fn _, _, _ -> :ok end)
    patch(Libp2pPort, :validate_message, fn _, _ -> :ok end)
    patch(BeaconChain, :get_fork_digest, fn -> "9999" end)
    patch(BeaconChain, :get_fork_version, fn -> "9999" end)
    patch(Metadata, :get_metadata, fn -> %{attnets: nil, syncnets: nil} end)
    :ok
  end

  defp attestation_data() do
    checkpoint_source = %Checkpoint{
      epoch: 3_776_037_760_046_644_755,
      root:
        <<29, 22, 191, 147, 188, 238, 162, 89, 147, 162, 202, 111, 169, 162, 84, 95, 194, 85, 54,
          172, 44, 74, 37, 128, 248, 21, 86, 246, 151, 54, 24, 54>>
    }

    checkpoint_target = %Checkpoint{
      epoch: 2_840_053_453_521_072_037,
      root:
        <<15, 174, 23, 120, 4, 9, 2, 116, 67, 73, 254, 53, 197, 3, 191, 166, 104, 34, 121, 2, 57,
          69, 75, 69, 254, 237, 132, 68, 254, 49, 127, 175>>
    }

    %AttestationData{
      slot: 5_057_010_135_270_197_978,
      index: 6_920_931_864_607_509_210,
      beacon_block_root:
        <<31, 38, 101, 174, 248, 168, 116, 226, 15, 39, 218, 148, 42, 8, 80, 80, 241, 149, 162,
          32, 176, 208, 120, 120, 89, 123, 136, 115, 154, 28, 21, 174>>,
      source: checkpoint_source,
      target: checkpoint_target
    }
  end

  @tag :tmp_dir
  test "stop collecting with one attestation" do
    subnet_id = 1

    expected_attestation = %Types.Attestation{
      data: attestation_data(),
      aggregation_bits: <<>>,
      signature: <<>>
    }

    Attestation.collect(subnet_id, expected_attestation)

    {:ok, attestations} = Attestation.stop_collecting(subnet_id)

    assert [expected_attestation] == attestations
  end

  @tag :tmp_dir
  test "stop collecting with two attestations" do
    subnet_id = 1

    attestation1 = %Types.Attestation{
      data: attestation_data(),
      aggregation_bits: <<>>,
      signature:
        <<1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
          1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
          1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
          1, 1, 1, 1, 1, 1, 1, 1, 1>>
    }

    attestation2 = %Types.Attestation{
      data: attestation_data(),
      aggregation_bits: <<>>,
      signature:
        <<2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
          2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
          2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
          2, 2, 2, 2, 2, 2, 2, 2, 2>>
    }

    Attestation.collect(subnet_id, attestation1)

    topic = Attestation.topic(subnet_id)
    {:ok, encoded_attestation} = Ssz.to_ssz(attestation2)
    {:ok, compressed_attestation} = :snappyer.compress(encoded_attestation)

    Attestation.handle_gossip_message(topic, 9999, compressed_attestation)

    {:ok, attestations} = Attestation.stop_collecting(subnet_id)

    assert [attestation2, attestation1] == attestations
  end
end
