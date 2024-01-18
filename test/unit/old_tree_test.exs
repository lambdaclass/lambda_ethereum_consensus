defmodule Unit.OldTreeTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.ForkChoice.OldTree
  alias LambdaEthereumConsensus.ForkChoice.OldTree.Node

  @root %Node{
    parent_id: :root,
    self_weight: 1,
    subtree_weight: 1,
    id: "root",
    children_ids: []
  }

  @node %Node{
    parent_id: "root",
    self_weight: 1,
    subtree_weight: 1,
    id: "node1",
    children_ids: []
  }

  setup do
    start_supervised!(OldTree)
    :ok
  end

  test "An empty tree returns a nil head" do
    assert OldTree.get_head() == nil
  end

  test "If there's just a root, it's the head" do
    OldTree.add_block(@root)
    assert OldTree.get_head() == @root
  end

  test "If there's two nodes, the head is the child" do
    OldTree.add_block(@root)
    OldTree.add_block(@node)
    assert OldTree.get_head() == @node
  end

  test "If there's three nodes, the head is the child with the highest weight" do
    heavy_node = @node |> Map.merge(%{self_weight: 2, id: "node 2", subtree_weight: 2})
    OldTree.add_block(@root)
    OldTree.add_block(@node)
    OldTree.add_block(heavy_node)
    assert OldTree.get_head() == heavy_node
  end

  test "If there's a parent is light but the subtree is heavy, it's still chosen" do
    heavy_node = @node |> Map.merge(%{self_weight: 2, id: "node 2", subtree_weight: 2})

    head_node =
      @node
      |> Map.merge(%{self_weight: 10, subtree_weight: 10, id: "node 3", parent_id: @node.id})

    OldTree.add_block(@root)
    OldTree.add_block(@node)
    OldTree.add_block(heavy_node)
    OldTree.add_block(head_node)
    assert OldTree.get_head() == head_node
  end
end
