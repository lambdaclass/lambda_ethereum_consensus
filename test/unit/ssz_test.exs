defmodule SSZTests do
  use ExUnit.Case

  def assert_roundtrip(%type{} = value) do
    assert {:ok, encoded} = Ssz.to_ssz(value)
    assert {:ok, decoded} = Ssz.from_ssz(encoded, type)

    assert decoded == value
  end

  test "serialize and deserialize checkpoint" do
    value = %SszTypes.Checkpoint{
      epoch: 12_345,
      root: Base.decode16!("0100000000000000000000000000000000000000000000000000000000000001")
    }

    assert_roundtrip(value)
  end

  test "serialize and deserialize fork" do
    value = %SszTypes.Fork{
      epoch: 5125,
      previous_version: <<1, 5, 4, 6>>,
      current_version: <<2, 5, 6, 0>>
    }

    assert_roundtrip(value)
  end

  test "serialize and deserialize fork data" do
    value = %SszTypes.ForkData{
      current_version: <<1, 5, 4, 6>>,
      genesis_validators_root:
        Base.decode16!("2E04DEB062423388AE42D465C4CC14CDD53AE290A7B4541F3217E26E0F039E83")
    }

    assert_roundtrip(value)
  end

  test "serialize and deserialize ExecutionPayloadHeader" do
    value = %SszTypes.ExecutionPayloadHeader{
      base_fee_per_gas:
        54_854_808_546_029_665_784_292_136_359_503_579_721_034_117_526_593_378_024_313_417_850_237_840_709_658,
      block_hash:
        Base.decode16!("126CB00648A774DC8139632C99ADD3ABA8AEA61FCB69FFA73C6AF5443F296A3A"),
      block_number: 8_071_210_002_511_434_893,
      extra_data: Base.decode16!("250A7CD78174E248A1CCCB0B04B09419210ECB0CE0D5062DA9922EFBF441"),
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

    assert_roundtrip(value)
  end

  test "serialize and deserialize status message" do
    serialized =
      Base.decode16!(
        "BBA4DA967715794499C07D9954DD223EC2C6B846D3BAB27956D093000FADC1B8219F74D4487B030000000000D62A74AE0F933224133C5E6E1827A2835A1E705F0CDFEE3AD25808DDEA5572DB4A696F0000000000"
      )

    deserialized = %SszTypes.StatusMessage{
      fork_digest: Base.decode16!("BBA4DA96"),
      finalized_root:
        Base.decode16!("7715794499C07D9954DD223EC2C6B846D3BAB27956D093000FADC1B8219F74D4"),
      finalized_epoch: 228_168,
      head_root:
        Base.decode16!("D62A74AE0F933224133C5E6E1827A2835A1E705F0CDFEE3AD25808DDEA5572DB"),
      head_slot: 7_301_450
    }

    assert {:ok, ^deserialized} = Ssz.from_ssz(serialized, SszTypes.StatusMessage)
    assert {:ok, ^serialized} = Ssz.to_ssz(deserialized)
  end
end
