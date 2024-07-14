defmodule Unit.Store.BlockBySlotTest do
  alias Fixtures.Random
  alias LambdaEthereumConsensus.Store.BlockBySlot

  use ExUnit.Case

  setup %{tmp_dir: tmp_dir} do
    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    :ok
  end

  @tag :tmp_dir
  test "Basic saving a block root" do
    root = Random.root()
    slot = Random.slot()
    assert :ok == BlockBySlot.put(slot, root)
    assert {:ok, root} == BlockBySlot.get(slot)
  end

  @tag :tmp_dir
  test "all_present? should return true when checking on a subset or the full set, but false for elements outside" do
    Enum.each(2..4, fn slot ->
      root = Random.root()
      assert :ok == BlockBySlot.put(slot, root)
    end)

    assert BlockBySlot.all_present?(2, 4)
    assert BlockBySlot.all_present?(3, 3)
    refute BlockBySlot.all_present?(1, 4)
    refute BlockBySlot.all_present?(2, 5)
    refute BlockBySlot.all_present?(1, 1)
  end

  @tag :tmp_dir
  test "all_present? should return false when elements are missing in between" do
    root = Random.root()
    BlockBySlot.put(1, root)
    BlockBySlot.put(3, root)

    assert BlockBySlot.all_present?(3, 3)
    assert BlockBySlot.all_present?(1, 1)
    refute BlockBySlot.all_present?(1, 3)
  end

  @tag :tmp_dir
  test "retrieving an empty slot" do
    assert :ok == BlockBySlot.put(1, :empty_slot)
    assert {:ok, :empty_slot} == BlockBySlot.get(1)
  end

  @tag :tmp_dir
  test "Trying to save an atom that's not :empty_slot fails" do
    assert_raise(FunctionClauseError, fn -> BlockBySlot.put(1, :some_atom) end)
  end

  @tag :tmp_dir
  test "Trying to save a non-root binary fails" do
    assert_raise(FunctionClauseError, fn -> BlockBySlot.put(1, "Hello") end)
  end
end
