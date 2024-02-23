defmodule Unit.SSZTests do
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

  test "serialize and deserialize ExecutionPayloadHeader" do
    assert_roundtrip(
      "7BE8A26D30CD185A4F1A4A45C3CAF9CF02AA48D87AD9DE86A16E9F7A9457428EBB8F77E9137CFB12A37740732280E9DC1E27703347249125256662644A1B10B6C77C4FC806A48FA50B9433FD8A1E645287446765ED0C1A1D20794883AF7E288479FB9108E40AB527BC5951C949B5A19A38A28C55026BA28AA54E581EDE27DE379708CF70266FE2C5A0ADD4A55C528E5FE886CD4C8D2075C4BD3779D89EE88C0FCFDDE4187FAE0D10E965A913AAAA4022D85FDE2A74BB191B0F259E3A438D38D8B30D742F2EFDCBB6EB5D0B8E63189EF8E854621F1E09BE4A92E0378CB234D314168E9FC7E526ECF893B7DDC59F617160EF66D7C8D37F09A17487A89EBE1E36CCEFCD657DFA9FFB087A1EBD482DB7EC1F14864BA5F3A2F7565B40B060340791DEC4516098B3E4E1AB9ABAF8FD3176CCCDBB485785EDF7F8BBBBB00CB4C9A6DD6ED9F3D9147FACF41A6FD8F21416BE9EC4C3D280F44AC57C63FCD8C970B89EF0F325DF06DD8F3DF30325BAB88DD1F9BDD8FEF5521457A72C099F2137971D83D83FB98825A4363E92851FC5C48D5E1366683418161B8D1446F3BBB202704D045D36B79D53C555CE1047B689C8742C3A936FDCBF9FF3380200001AD812FE3E0E198AE176099C93263A3205C401E629914A7D221D8289ACB84679126CB00648A774DC8139632C99ADD3ABA8AEA61FCB69FFA73C6AF5443F296A3AF9ED0498257B56CF3A92AB1E2ECDCA53BBBF18A3AC5135C9FFEC570F81CCE3DAD8F6FD5537A4D36B61DC29A1741DC55150F6D7DC6ADFFD5CF208257B25DDD809250A7CD78174E248A1CCCB0B04B09419210ECB0CE0D5062DA9922EFBF441",
      %Types.ExecutionPayloadHeader{
        base_fee_per_gas:
          54_854_808_546_029_665_784_292_136_359_503_579_721_034_117_526_593_378_024_313_417_850_237_840_709_658,
        block_hash:
          Base.decode16!("126CB00648A774DC8139632C99ADD3ABA8AEA61FCB69FFA73C6AF5443F296A3A"),
        block_number: 8_071_210_002_511_434_893,
        extra_data:
          Base.decode16!("250A7CD78174E248A1CCCB0B04B09419210ECB0CE0D5062DA9922EFBF441"),
        fee_recipient: Base.decode16!("BB8F77E9137CFB12A37740732280E9DC1E277033"),
        gas_limit: 14_218_881_858_755_429_453,
        gas_used: 8_415_127_319_711_108_693,
        logs_bloom:
          Base.decode16!(
            "026BA28AA54E581EDE27DE379708CF70266FE2C5A0ADD4A55C528E5FE886CD4C8D2075C4BD3779D89EE88C0FCFDDE4187FAE0D10E965A913AAAA4022D85FDE2A74BB191B0F259E3A438D38D8B30D742F2EFDCBB6EB5D0B8E63189EF8E854621F1E09BE4A92E0378CB234D314168E9FC7E526ECF893B7DDC59F617160EF66D7C8D37F09A17487A89EBE1E36CCEFCD657DFA9FFB087A1EBD482DB7EC1F14864BA5F3A2F7565B40B060340791DEC4516098B3E4E1AB9ABAF8FD3176CCCDBB485785EDF7F8BBBBB00CB4C9A6DD6ED9F3D9147FACF41A6FD8F21416BE9EC4C3D280F44AC57C63FCD8C970B89EF0F325DF06DD8F3DF30325BAB88DD1F9BDD8FEF55214"
          ),
        parent_hash:
          Base.decode16!("7BE8A26D30CD185A4F1A4A45C3CAF9CF02AA48D87AD9DE86A16E9F7A9457428E"),
        prev_randao:
          Base.decode16!("57A72C099F2137971D83D83FB98825A4363E92851FC5C48D5E1366683418161B"),
        receipts_root:
          Base.decode16!("ED0C1A1D20794883AF7E288479FB9108E40AB527BC5951C949B5A19A38A28C55"),
        state_root:
          Base.decode16!("47249125256662644A1B10B6C77C4FC806A48FA50B9433FD8A1E645287446765"),
        timestamp: 17_554_960_825_999_112_748,
        transactions_root:
          Base.decode16!("F9ED0498257B56CF3A92AB1E2ECDCA53BBBF18A3AC5135C9FFEC570F81CCE3DA"),
        withdrawals_root:
          Base.decode16!("D8F6FD5537A4D36B61DC29A1741DC55150F6D7DC6ADFFD5CF208257B25DDD809")
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
end
