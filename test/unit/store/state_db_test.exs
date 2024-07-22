defmodule Unit.Store.StateDb do
  alias Fixtures.Random
  alias LambdaEthereumConsensus.Store.StateDb
  alias Types.StateInfo
  alias Types.BeaconState

  use ExUnit.Case

  setup_all do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.put(:config, MinimalConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))
  end

  setup %{tmp_dir: tmp_dir} do
    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    :ok
  end

  defp get_state_info() do
    {:ok, encoded} =
      File.read!("test/fixtures/validator/proposer/beacon_state.ssz_snappy")
      |> :snappyer.decompress()

    {:ok, decoded} = SszEx.decode(encoded, BeaconState)
    {:ok, state_info} = StateInfo.from_beacon_state(decoded)
    state_info
  end

  @tag :tmp_dir
  test "Get on a non-existent block root" do
    root = Random.root()
    assert :not_found == StateDb.get_state_by_block_root(root)
  end

  @tag :tmp_dir
  test "Get on a non-existent state root" do
    root = Random.root()
    assert :not_found == StateDb.get_state_by_state_root(root)
  end

  @tag :tmp_dir
  test "Get on a non-existent slot" do
    slot = Random.slot()
    assert :not_found == StateDb.get_state_by_slot(slot)
  end

  @tag :tmp_dir
  test "Basic saving a state" do
    state = get_state_info()

    assert :ok == StateDb.store_state_info(state)

    assert {:ok, state} == StateDb.get_state_by_block_root(state.block_root)
    assert {:ok, state} == StateDb.get_state_by_state_root(state.root)
    assert {:ok, state} == StateDb.get_state_by_slot(state.beacon_state.slot)
  end
end
