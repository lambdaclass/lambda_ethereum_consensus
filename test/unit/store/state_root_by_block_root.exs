defmodule Unit.Store.StateRootByBlockRoot do
  alias Fixtures.Random
  alias LambdaEthereumConsensus.Store.StateDb.StateRootByBlockRoot

  use ExUnit.Case

  setup %{tmp_dir: tmp_dir} do
    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    :ok
  end

  @tag :tmp_dir
  test "Get on a non-existent slot" do
    root = Random.root()
    assert :not_found == StateRootByBlockRoot.get(root)
  end

  @tag :tmp_dir
  test "Basic saving a block root" do
    block_root = Random.root()
    state_root = Random.root()
    assert :ok == StateRootByBlockRoot.put(block_root, state_root)
    assert {:ok, state_root} == StateRootByBlockRoot.get(block_root)
  end

  @tag :tmp_dir
  test "Basic saving two block roots" do
    state_root1 = Random.root()
    block_root1 = Random.root()
    state_root2 = Random.root()
    block_root2 = Random.root()

    assert :ok == StateRootByBlockRoot.put(block_root1, state_root1)
    assert :ok == StateRootByBlockRoot.put(block_root2, state_root2)

    assert {:ok, state_root1} == StateRootByBlockRoot.get(block_root1)
    assert {:ok, state_root2} == StateRootByBlockRoot.get(block_root2)
  end

  @tag :tmp_dir
  test "Delete one root" do
    state_root1 = Random.root()
    block_root1 = Random.root()
    state_root2 = Random.root()
    block_root2 = Random.root()

    assert :ok == StateRootByBlockRoot.put(block_root1, state_root1)
    assert :ok == StateRootByBlockRoot.put(block_root2, state_root2)
    assert :ok == StateRootByBlockRoot.delete(block_root2)

    assert {:ok, state_root1} == StateRootByBlockRoot.get(block_root1)
    assert :not_found == StateRootByBlockRoot.get(block_root2)
  end

  @tag :tmp_dir
  test "Trying to save a non-root binary fails" do
    assert_raise(FunctionClauseError, fn -> StateRootByBlockRoot.put(1, "Hello") end)
  end
end
