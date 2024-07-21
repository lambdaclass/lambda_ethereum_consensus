defmodule Unit.Store.StateDb.BlockRootBySlotTest do
  alias Fixtures.Random
  alias LambdaEthereumConsensus.Store.StateDb.BlockRootBySlot

  use ExUnit.Case

  setup %{tmp_dir: tmp_dir} do
    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    :ok
  end

  @tag :tmp_dir
  test "Get on a non-existent slot" do
    slot = Random.slot()
    assert :not_found == BlockRootBySlot.get(slot)




  end

  @tag :tmp_dir
  test "Basic saving a block root" do
    root = Random.root()
    slot = Random.slot()
    assert :ok == BlockRootBySlot.put(slot, root)
    assert {:ok, root} == BlockRootBySlot.get(slot)
  end

  @tag :tmp_dir
  test "Basic saving two block roots" do
    root1 = Random.root()
    slot1 = Random.slot()
    root2 = Random.root()
    slot2 = Random.slot()

    assert :ok == BlockRootBySlot.put(slot1, root1)
    assert :ok == BlockRootBySlot.put(slot2, root2)

    assert {:ok, root1} == BlockRootBySlot.get(slot1)
    assert {:ok, root2} == BlockRootBySlot.get(slot2)
  end

  @tag :tmp_dir
  test "Delete one slot" do
    root1 = Random.root()
    slot1 = Random.slot()
    root2 = Random.root()
    slot2 = Random.slot()

    assert :ok == BlockRootBySlot.put(slot1, root1)
    assert :ok == BlockRootBySlot.put(slot2, root2)
    assert :ok == BlockRootBySlot.delete(slot2)

    assert {:ok, root1} == BlockRootBySlot.get(slot1)
    assert :not_found == BlockRootBySlot.get(slot2)
  end

    @tag :tmp_dir
  test "Get the root of the last slot" do
      [root1, root2, root3] =
      [Random.root(), Random.root(), Random.root()]
      [slot1, slot2, slot3] =
      [Random.slot(), Random.slot(), Random.slot()]
      |> Enum.sort()

    assert :ok == BlockRootBySlot.put(slot1, root1)
    assert :ok == BlockRootBySlot.put(slot2, root2)
    assert :ok == BlockRootBySlot.put(slot3, root3)

    # Check that the keys are present
  assert {:ok, root1} == BlockRootBySlot.get(slot1)
  assert {:ok, root2} == BlockRootBySlot.get(slot2)
  assert {:ok, root3} == BlockRootBySlot.get(slot3)


    assert {:ok, root2} == BlockRootBySlot.get_last_slot_block_root(slot3)
  end

  @tag :tmp_dir
  test "Trying to save a non-root binary fails" do
    assert_raise(FunctionClauseError, fn -> BlockRootBySlot.put(1, "Hello") end)
  end
end
