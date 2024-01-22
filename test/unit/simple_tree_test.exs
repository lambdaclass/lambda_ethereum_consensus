defmodule Unit.SimpleTreeTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.ForkChoice.Simple.Tree

  test "Create a tree" do
    Tree.new("root")
  end

  test "Add new blocks to the tree" do
    tree =
      Tree.new("root")
      |> Tree.add_block!("root_child1", "root")
      |> Tree.add_block!("root_child2", "root")
      |> Tree.add_block!("root_child1_child", "root_child1")

    # We use MapSet to ignore the order of the blocks
    expected = MapSet.new(["root_child1", "root_child2"])
    root_children = Tree.get_children!(tree, "root") |> MapSet.new()

    assert MapSet.equal?(root_children, expected)

    assert Tree.get_children!(tree, "root_child1") == ["root_child1_child"]
    assert Tree.get_children!(tree, "root_child1_child") == []
    assert Tree.get_children!(tree, "root_child2") == []
  end

  test "Update the tree's root" do
    tree =
      Tree.new("root")
      |> Tree.add_block!("root_child1", "root")
      |> Tree.add_block!("root_child2", "root")
      |> Tree.add_block!("root_child1_child", "root_child1")
      # Update tree's root and prune pre-root blocks
      |> Tree.update_root!("root_child1")

    expected_tree =
      Tree.new("root_child1")
      |> Tree.add_block!("root_child1_child", "root_child1")

    assert tree == expected_tree

    error = {:error, :not_found}
    assert Tree.get_children(tree, "root") == error, "root should be pruned"
    assert Tree.get_children(tree, "root_child2") == error, "cousins should be pruned"

    assert Tree.get_children!(tree, "root_child1") == ["root_child1_child"]
    assert Tree.get_children!(tree, "root_child1_child") == []
  end
end
