defmodule Unit.Store.StateDb do
  alias Fixtures.Random
  alias LambdaEthereumConsensus.Store.StateDb
  alias Types.BeaconState
  alias Types.StateInfo

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

  @tag :tmp_dir
  test "Basic saving of two states" do
    state1 = get_state_info()
    beacon_state2 = state1.beacon_state |> Map.put(:slot, state1.beacon_state.slot + 1)

    state2 =
      state1
      |> Map.put(:beacon_state, beacon_state2)
      |> Map.put(:block_root, Random.root())
      |> Map.put(:root, Random.root())

    assert :ok == StateDb.store_state_info(state1)
    assert :ok == StateDb.store_state_info(state2)

    assert {:ok, state1} == StateDb.get_state_by_block_root(state1.block_root)
    assert {:ok, state1} == StateDb.get_state_by_state_root(state1.root)
    # assert {:ok, state1} == StateDb.get_state_by_slot(state1.beacon_state.slot)

    {:ok, result_state} = StateDb.get_state_by_state_root(state2.root)
    assert :unchanged == LambdaEthereumConsensus.Utils.Diff.diff(result_state, state2)
    # assert {:ok, state2} == StateDb.get_state_by_block_root(state2.block_root)
    # assert {:ok, state2} == StateDb.get_state_by_slot(state2.beacon_state.slot)
  end
end
