defmodule Unit.Store.StateInfoByRoot do
  alias Fixtures.Random
  alias LambdaEthereumConsensus.Store.StateDb.StateInfoByRoot
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
  test "Get on a non-existent root" do
    root = Random.root()
    assert :not_found == StateInfoByRoot.get(root)
  end

  @tag :tmp_dir
  test "Basic saving a state" do
    state = get_state_info()
    assert :ok == StateInfoByRoot.put(state.root, state)
    assert {:ok, state} == StateInfoByRoot.get(state.root)
  end

  @tag :tmp_dir
  test "Delete one state" do
    state = get_state_info()
    state_root1 = Random.root()
    state_root2 = Random.root()

    assert :ok == StateInfoByRoot.put(state_root1, state)
    assert :ok == StateInfoByRoot.put(state_root2, state)
    assert :ok == StateInfoByRoot.delete(state_root2)

    assert {:ok, state} == StateInfoByRoot.get(state_root1)
    assert :not_found == StateInfoByRoot.get(state_root2)
  end

  @tag :tmp_dir
  test "Trying to save a different type fails" do
    assert_raise(FunctionClauseError, fn -> StateInfoByRoot.put(1, "Hello") end)
  end
end
