defmodule Unit.TreeTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.ForkChoice.Tree
  alias LambdaEthereumConsensus.ForkChoice.Tree.Node

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
    start_supervised!(Tree)
    :ok
  end

  test "An empty tree returns a nil head" do
    assert Tree.get_head() == nil
  end

  test "If there's just a root, it's the head" do
    Tree.add_block(@root)
    assert Tree.get_head() == @root
  end

  test "If there's two nodes, the head is the child" do
    Tree.add_block(@root)
    Tree.add_block(@node)
    assert Tree.get_head() == @node
  end

  test "If there's three nodes, the head is the child with the highest weight" do
    heavy_node = @node |> Map.merge(%{self_weight: 2, id: "node 2", subtree_weight: 2})
    Tree.add_block(@root)
    Tree.add_block(@node)
    Tree.add_block(heavy_node)
    assert Tree.get_head() == heavy_node
  end
end
