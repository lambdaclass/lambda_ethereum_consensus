defmodule Unit.AttestationTest do
  alias LambdaEthereumConsensus.Store.Db
  alias Types.Checkpoint
  alias Types.SyncCommitteeMessage
  alias Types.SyncSubnetInfo

  use ExUnit.Case
  use Patch

  doctest SyncSubnetInfo

  setup %{tmp_dir: tmp_dir} do
    start_link_supervised!({Db, dir: tmp_dir})
    :ok
  end

  defp sync_committee_message(validator_index \\ 0) do
    %SyncCommitteeMessage{
      slot: 5_057_010_135_270_197_978,
      beacon_block_root:
        <<31, 38, 101, 174, 248, 168, 116, 226, 15, 39, 218, 148, 42, 8, 80, 80, 241, 149, 162,
          32, 176, 208, 120, 120, 89, 123, 136, 115, 154, 28, 21, 174>>,
      validator_index: validator_index,
      signature: <<>>
    }
  end

  @tag :tmp_dir
  test "stop collecting with one attestation" do
    subnet_id = 1

    expected_message = %SyncCommitteeMessage{
      slot: 5_057_010_135_270_197_978,
      beacon_block_root:
        <<31, 38, 101, 174, 248, 168, 116, 226, 15, 39, 218, 148, 42, 8, 80, 80, 241, 149, 162,
          32, 176, 208, 120, 120, 89, 123, 136, 115, 154, 28, 21, 174>>,
      validator_index: 0,
      signature: <<>>
    }

    SyncSubnetInfo.new_subnet_with_message(subnet_id, sync_committee_message())

    {:ok, messages} = SyncSubnetInfo.stop_collecting(subnet_id)

    assert [expected_message] == messages
  end

  @tag :tmp_dir
  test "stop collecting with two attestations" do
    subnet_id = 1

    expected_message_1 = %SyncCommitteeMessage{
      slot: 5_057_010_135_270_197_978,
      beacon_block_root:
        <<31, 38, 101, 174, 248, 168, 116, 226, 15, 39, 218, 148, 42, 8, 80, 80, 241, 149, 162,
          32, 176, 208, 120, 120, 89, 123, 136, 115, 154, 28, 21, 174>>,
      validator_index: 1,
      signature: <<>>
    }

    expected_message_2 = %SyncCommitteeMessage{
      slot: 5_057_010_135_270_197_978,
      beacon_block_root:
        <<31, 38, 101, 174, 248, 168, 116, 226, 15, 39, 218, 148, 42, 8, 80, 80, 241, 149, 162,
          32, 176, 208, 120, 120, 89, 123, 136, 115, 154, 28, 21, 174>>,
      validator_index: 2,
      signature: <<>>
    }

    SyncSubnetInfo.new_subnet_with_message(subnet_id, sync_committee_message(1))

    SyncSubnetInfo.add_message!(subnet_id, sync_committee_message(2))

    {:ok, messages} = SyncSubnetInfo.stop_collecting(subnet_id)

    assert [expected_message_2, expected_message_1] == messages
  end
end
