defmodule Unit.TreeTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.ForkChoice.Tree

  test "Create a tree" do
    Tree.new("root")
  end

  test "Add new blocks to the tree" do
    blocks = [
      {"root_child1", "root"},
      {"root_child2", "root"},
      {"root_child1_child", "root_child1"}
    ]

    tree_blocks =
      blocks
      |> Enum.reduce(Tree.new("root"), fn {block, parent}, tree ->
        Tree.add_block!(tree, block, parent)
      end)
      |> Tree.get_all_blocks()

    # We use MapSet to ignore the order of the blocks
    expected_blocks = MapSet.new([{"root", :root} | blocks])
    assert MapSet.equal?(MapSet.new(tree_blocks), expected_blocks)
  end

  test "Update the tree's root" do
    pruned_tree =
      Tree.new("root")
      |> Tree.add_block!("root_child1", "root")
      |> Tree.add_block!("root_child2", "root")
      |> Tree.add_block!("root_child1_child", "root_child1")
      # Update tree's root and prune pre-root blocks
      |> Tree.update_root!("root_child1")

    expected_tree =
      Tree.new("root_child1")
      |> Tree.add_block!("root_child1_child", "root_child1")

    assert pruned_tree == expected_tree

    expected_blocks =
      MapSet.new([{"root_child1", :root}, {"root_child1_child", "root_child1"}])

    blocks = pruned_tree |> Tree.get_all_blocks() |> MapSet.new()

    assert MapSet.equal?(blocks, expected_blocks)
  end
end
