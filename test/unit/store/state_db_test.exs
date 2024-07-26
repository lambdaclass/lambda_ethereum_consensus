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

  # Returns a new `state_info` with:
  # - `slot` incremented by 1.
  # - A random `block_root`.
  # - A random `state_root`.
  defp modify_state_info(state_info) do
    new_beacon_state = state_info.beacon_state |> Map.put(:slot, state_info.beacon_state.slot + 1)
    {:ok, new_state_info} = StateInfo.from_beacon_state(new_beacon_state)

    new_state_info
    |> Map.put(:block_root, Random.root())
  end

  defp assert_state_is_present(state) do
    assert {:ok, state} == StateDb.get_state_by_block_root(state.block_root)
    assert {:ok, state} == StateDb.get_state_by_state_root(state.root)
    assert {:ok, state} == StateDb.get_state_by_slot(state.beacon_state.slot)
  end

  defp assert_state_not_found(state) do
    assert :not_found == StateDb.get_state_by_block_root(state.block_root)
    assert :not_found == StateDb.get_state_by_state_root(state.root)
    assert :not_found == StateDb.get_state_by_slot(state.beacon_state.slot)
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

    assert_state_is_present(state)
  end

  @tag :tmp_dir
  test "Basic saving of two states" do
    state1 = get_state_info()
    state2 = modify_state_info(state1)

    assert :ok == StateDb.store_state_info(state1)
    assert :ok == StateDb.store_state_info(state2)

    assert_state_is_present(state1)
    assert_state_is_present(state2)
  end

  @tag :tmp_dir
  test "Pruning from the first slot" do
    state1 = get_state_info()
    state2 = modify_state_info(state1)
    state3 = modify_state_info(state2)

    assert :ok == StateDb.store_state_info(state1)
    assert :ok == StateDb.store_state_info(state2)
    assert :ok == StateDb.store_state_info(state3)

    assert_state_is_present(state1)
    assert_state_is_present(state2)
    assert_state_is_present(state3)

    assert :ok == StateDb.prune_states_older_than(state1.beacon_state.slot)

    assert_state_is_present(state1)
    assert_state_is_present(state2)
    assert_state_is_present(state3)
  end

  @tag :tmp_dir
  test "Pruning from the last slot" do
    state1 = get_state_info()
    state2 = modify_state_info(state1)
    state3 = modify_state_info(state2)

    assert :ok == StateDb.store_state_info(state1)
    assert :ok == StateDb.store_state_info(state2)
    assert :ok == StateDb.store_state_info(state3)

    assert_state_is_present(state1)
    assert_state_is_present(state2)
    assert_state_is_present(state3)

    assert :ok == StateDb.prune_states_older_than(state3.beacon_state.slot)

    assert_state_not_found(state1)
    assert_state_not_found(state2)
    assert_state_is_present(state3)
  end

  @tag :tmp_dir
  test "Get latest state when empty" do
    assert :not_found == StateDb.get_latest_state()
  end

  @tag :tmp_dir
  test "Get latest state with one state" do
    state = get_state_info()

    assert :ok == StateDb.store_state_info(state)

    assert {:ok, state} == StateDb.get_latest_state()
  end

  @tag :tmp_dir
  test "Get latest state with many states" do
    state1 = get_state_info()
    state2 = modify_state_info(state1)
    state3 = modify_state_info(state2)

    assert :ok == StateDb.store_state_info(state1)
    assert :ok == StateDb.store_state_info(state2)
    assert :ok == StateDb.store_state_info(state3)

    assert {:ok, state3} == StateDb.get_latest_state()
  end
end
