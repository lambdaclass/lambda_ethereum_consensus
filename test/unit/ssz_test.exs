defmodule Unit.SSZTests do
  alias Fixtures.Block
  alias LambdaEthereumConsensus.Utils.BitVector
  use ExUnit.Case

  setup_all do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.put(:config, MainnetConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))
  end

  def assert_roundtrip(hex_serialized, %type{} = deserialized) do
    serialized = Base.decode16!(hex_serialized)
    assert {:ok, ^serialized} = Ssz.to_ssz(deserialized)
    assert {:ok, ^deserialized} = Ssz.from_ssz(serialized, type)
  end

  test "serialize and deserialize checkpoint" do
    assert_roundtrip(
      "39300000000000000100000000000000000000000000000000000000000000000000000000000001",
      %Types.Checkpoint{
        epoch: 12_345,
        root: Base.decode16!("0100000000000000000000000000000000000000000000000000000000000001")
      }
    )
  end

  test "serialize and deserialize fork" do
    assert_roundtrip(
      "01050406020506000514000000000000",
      %Types.Fork{
        epoch: 5125,
        previous_version: "01050406" |> Base.decode16!(),
        current_version: "02050600" |> Base.decode16!()
      }
    )
  end

  test "hash fork" do
    value = %Types.Fork{
      epoch: 5125,
      previous_version: <<1, 5, 4, 6>>,
      current_version: <<2, 5, 6, 0>>
    }

    expected = Base.decode16!("02706479366CF66D8103DFBE45193F8B5A0511A18B235E9742621B0148D26D14")

    assert {:ok, expected} == Ssz.hash_tree_root(value)
  end

  test "serialize and deserialize fork data" do
    assert_roundtrip(
      "010504062E04DEB062423388AE42D465C4CC14CDD53AE290A7B4541F3217E26E0F039E83",
      %Types.ForkData{
        current_version: "01050406" |> Base.decode16!(),
        genesis_validators_root:
          Base.decode16!("2E04DEB062423388AE42D465C4CC14CDD53AE290A7B4541F3217E26E0F039E83")
      }
    )
  end

  test "serialize and deserialize status message" do
    assert_roundtrip(
      "BBA4DA967715794499C07D9954DD223EC2C6B846D3BAB27956D093000FADC1B8219F74D4487B030000000000D62A74AE0F933224133C5E6E1827A2835A1E705F0CDFEE3AD25808DDEA5572DB4A696F0000000000",
      %Types.StatusMessage{
        fork_digest: Base.decode16!("BBA4DA96"),
        finalized_root:
          Base.decode16!("7715794499C07D9954DD223EC2C6B846D3BAB27956D093000FADC1B8219F74D4"),
        finalized_epoch: 228_168,
        head_root:
          Base.decode16!("D62A74AE0F933224133C5E6E1827A2835A1E705F0CDFEE3AD25808DDEA5572DB"),
        head_slot: 7_301_450
      }
    )
  end

  test "serialize and deserialize BeaconBlocksByRangeRequest" do
    assert_roundtrip(
      "9D080B000000000064000000000000000100000000000000",
      %Types.BeaconBlocksByRangeRequest{
        start_slot: 723_101,
        count: 100,
        step: 1
      }
    )
  end

  test "serialize and deserialize Metadata" do
    assert_roundtrip(
      "E1ED6200000000009989AFAE2372EC4C07",
      %Types.Metadata{
        seq_number: 6_483_425,
        attnets: Base.decode16!("9989AFAE2372EC4C") |> BitVector.new(64),
        syncnets: Base.decode16!("07") |> BitVector.new(4)
      }
    )
  end

  test "serialize and hash list of VoluntaryExit" do
    deserialized = [
      %Types.VoluntaryExit{
        epoch: 556,
        validator_index: 67_247
      },
      %Types.VoluntaryExit{
        epoch: 6167,
        validator_index: 73_838
      },
      %Types.VoluntaryExit{
        epoch: 738,
        validator_index: 838_883
      }
    ]

    # Because VoluntaryExits are fixed size
    serialized =
      deserialized
      |> Stream.map(fn v ->
        assert {:ok, v} = Ssz.to_ssz(v)
        v
      end)
      |> Enum.join()

    assert {:ok, ^serialized} = Ssz.to_ssz(deserialized)
    assert {:ok, ^deserialized} = Ssz.list_from_ssz(serialized, Types.VoluntaryExit)
    assert {:ok, _hash} = Ssz.hash_list_tree_root(deserialized, 4)
  end

  test "serialize and hash list of transactions" do
    # These would be bytes
    t1 = "asfasfas"
    t2 = "18418280192"
    t3 = "zd9g8as0f70a0sf"

    deserialized = [t1, t2, t3]

    initial_offset = length(deserialized) * 4

    serialized =
      Enum.join([
        <<initial_offset::32-little>>,
        <<initial_offset + byte_size(t1)::32-little>>,
        <<initial_offset + byte_size(t1) + byte_size(t2)::32-little>>,
        Enum.join(deserialized)
      ])

    assert serialized ==
             Base.decode16!(
               "0C000000140000001F000000617366617366617331383431383238303139327A6439673861733066373061307366"
             )

    assert {:ok, ^serialized} = Ssz.to_ssz_typed(deserialized, Types.Transaction)
    assert {:ok, ^deserialized} = Ssz.list_from_ssz(serialized, Types.Transaction)

    hash = Base.decode16!("D5ACD42F851C9AE241B55AB79B23D7EC613E01BB6404B4A49D8CF214DBA26CF2")

    assert {:ok, ^hash} =
             Ssz.hash_list_tree_root_typed(deserialized, 1_048_576, Types.Transaction)
  end

  test "serialize and hash epoch" do
    assert {:ok, _hash} = Ssz.hash_tree_root(10_991_501_063_301_624_660, Types.Epoch)
  end

  test "BlobIdentifier" do
    identifier = %Types.BlobIdentifier{
      block_root:
        Base.decode16!("2372E5421A2D08538F385A4BC98DBCF5763E71092E8290F611FFE996FCA2E8E4"),
      index: 1
    }

    assert {:ok, _hash} = Ssz.hash_tree_root(identifier)
    {:ok, encoded} = Ssz.to_ssz(identifier)
    assert {:ok, ^identifier} = Ssz.from_ssz(encoded, Types.BlobIdentifier)
  end

  test "BlobSidecar" do
    # seed RNG
    :rand.seed(:default, 0)
    header = Block.signed_beacon_block_header()

    sidecar = %Types.BlobSidecar{
      index: 1,
      blob: <<152_521_252::(4096*32)*8>>,
      kzg_commitment: <<57_888::48*8>>,
      kzg_proof: <<6122::48*8>>,
      signed_block_header: header,
      kzg_commitment_inclusion_proof: [<<1551::32*8>>] |> Stream.cycle() |> Enum.take(17)
    }

    assert {:ok, _hash} = Ssz.hash_tree_root(sidecar)
    {:ok, encoded} = Ssz.to_ssz(sidecar)
    assert {:ok, ^sidecar} = Ssz.from_ssz(encoded, Types.BlobSidecar)
  end

  test "SignedBeaconBlock" do
    # seed RNG
    :rand.seed(:default, 0)
    random_block = Block.signed_beacon_block()

    random_payload = Block.execution_payload()

    execution_payload =
      struct!(
        Types.ExecutionPayload,
        random_payload
        |> Map.from_struct()
        |> Map.merge(%{blob_gas_used: 1, excess_blob_gas: 1})
      )

    new_body =
      struct!(
        Types.BeaconBlockBody,
        random_block.message.body
        |> Map.from_struct()
        |> Map.merge(%{
          execution_payload: execution_payload,
          blob_kzg_commitments: [<<125_125::48*8>>]
        })
      )

    deneb_block = %Types.SignedBeaconBlock{
      message:
        struct!(
          Types.BeaconBlock,
          random_block.message
          |> Map.from_struct()
          |> Map.merge(%{body: new_body})
        ),
      signature: random_block.signature
    }

    assert {:ok, _hash} = Ssz.hash_tree_root(deneb_block)
    {:ok, encoded} = Ssz.to_ssz(deneb_block)
    assert {:ok, ^deneb_block} = Ssz.from_ssz(encoded, Types.SignedBeaconBlock)
  end
end
