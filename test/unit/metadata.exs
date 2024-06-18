defmodule Unit.AttestationTest do
  alias LambdaEthereumConsensus.P2P.Metadata
  alias LambdaEthereumConsensus.Utils.BitVector

  use ExUnit.Case

  doctest Metadata

  setup %{tmp_dir: tmp_dir} do
    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    start_link_supervised!(Metadata)
    :ok
  end

  @tag :tmp_dir
  test "init metadata" do
    assert Metadata.get_metadata() == Types.Metadata.empty()
    assert Metadata.get_seq_number() == 0
  end

  @tag :tmp_dir
  test "set and clear attnet" do
    attnet_index = 5

    expected_attnet =
      ChainSpec.get("ATTESTATION_SUBNET_COUNT") |> BitVector.new() |> BitVector.set(attnet_index)

    Metadata.set_attnet(attnet_index)
    new_metadata = Metadata.get_metadata()

    assert new_metadata.attnets == expected_attnet
    assert new_metadata.seq_number == 1

    Metadata.clear_attnet(5)
    new_metadata = Metadata.get_metadata()

    expected_attnet =
      ChainSpec.get("ATTESTATION_SUBNET_COUNT") |> BitVector.new()

    assert new_metadata.attnets == expected_attnet
    assert new_metadata.seq_number == 2
  end

  @tag :tmp_dir
  test "set and clear syncnet" do
    syncnet_index = 2

    expected_syncnet =
      Constants.sync_committee_subnet_count() |> BitVector.new() |> BitVector.set(syncnet_index)

    Metadata.set_syncnet(syncnet_index)
    new_metadata = Metadata.get_metadata()

    assert new_metadata.syncnets == expected_syncnet
    assert new_metadata.seq_number == 1

    Metadata.clear_syncnet(2)
    new_metadata = Metadata.get_metadata()

    expected_syncnet =
      Constants.sync_committee_subnet_count() |> BitVector.new()

    assert new_metadata.syncnets == expected_syncnet
    assert new_metadata.seq_number == 2
  end

  @tag :tmp_dir
  test "syncnet and attnet" do
    # set attnet
    attnet_index = 5

    expected_attnet =
      ChainSpec.get("ATTESTATION_SUBNET_COUNT") |> BitVector.new() |> BitVector.set(attnet_index)

    Metadata.set_attnet(attnet_index)

    # set syncnet
    syncnet_index = 2

    expected_syncnet =
      Constants.sync_committee_subnet_count() |> BitVector.new() |> BitVector.set(syncnet_index)

    Metadata.set_syncnet(syncnet_index)

    # check metadata
    new_metadata = Metadata.get_metadata()

    assert new_metadata.syncnets == expected_syncnet
    assert new_metadata.attnets == expected_attnet
    assert new_metadata.seq_number == 2

    # clear syncnet
    Metadata.clear_syncnet(2)
    new_metadata = Metadata.get_metadata()

    expected_syncnet =
      Constants.sync_committee_subnet_count() |> BitVector.new()

    assert new_metadata.syncnets == expected_syncnet
    assert new_metadata.seq_number == 3

    # clear attnet
    Metadata.clear_attnet(5)
    new_metadata = Metadata.get_metadata()

    expected_attnet =
      ChainSpec.get("ATTESTATION_SUBNET_COUNT") |> BitVector.new()

    assert new_metadata.attnets == expected_attnet
    assert new_metadata.seq_number == 4
  end
end
