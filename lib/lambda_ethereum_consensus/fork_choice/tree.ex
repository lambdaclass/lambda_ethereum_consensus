defmodule LambdaEthereumConsensus.ForkChoice.Tree do
  @moduledoc false

  defmodule Node do
    @moduledoc false
    defstruct [:parent_id, :id, :children_ids]
    @type id :: Types.root()
    @type parent_id :: id() | :root
    @type t :: %__MODULE__{
            parent_id: parent_id(),
            id: id,
            children_ids: [id]
          }
  end

  @enforce_keys [:root, :nodes]
  defstruct [:root, :nodes]

  @type t() :: %__MODULE__{root: Node.id(), nodes: %{Node.id() => Node.t()}}

  ##########################
  ### Public API
  ##########################

  @spec new(Node.id()) :: t()
  def new(root) when is_binary(root) do
    root_node = %Node{parent_id: :root, id: root, children_ids: []}
    %__MODULE__{root: root, nodes: %{root => root_node}}
  end

  @spec add_block(t(), Node.id(), Node.id()) :: {:ok, t()} | {:error, :not_found}
  def add_block(%__MODULE__{} = tree, block_root, parent_root) do
    node = %Node{
      parent_id: parent_root,
      id: block_root,
      children_ids: []
    }

    with {:ok, new_nodes} <- add_node_to_tree(tree.nodes, node) do
      {:ok, %{tree | nodes: new_nodes}}
    end
  end

  @spec add_block!(t(), Node.id(), Node.id()) :: t()
  def add_block!(tree, block_root, parent_root) do
    case add_block(tree, block_root, parent_root) do
      {:error, :not_found} -> raise "Parent #{Base.encode16(parent_root)} not found in tree"
      {:ok, new_tree} -> new_tree
    end
  end

  @spec update_root(t(), Node.id()) :: {:ok, t()} | {:error, :not_found}
  def update_root(%__MODULE__{nodes: nodes}, new_root) do
    case Map.get(nodes, new_root) do
      nil ->
        {:error, :not_found}

      node ->
        get_subtree(nodes, %{node | parent_id: :root})
        |> Map.new(fn node -> {node.id, node} end)
        |> then(&{:ok, %__MODULE__{root: new_root, nodes: &1}})
    end
  end

  @spec update_root!(t(), Node.id()) :: t()
  def update_root!(tree, new_root) do
    case update_root(tree, new_root) do
      {:error, :not_found} -> raise "Root #{Base.encode16(new_root)} not found in tree"
      {:ok, new_tree} -> new_tree
    end
  end

  @spec get_all_blocks(t()) :: [{Node.id(), Node.parent_id()}]
  def get_all_blocks(%{nodes: nodes}),
    do: nodes |> Enum.map(fn {id, %{parent_id: p_id}} -> {id, p_id} end)

  ##########################
  ### Private Functions
  ##########################

  defp add_node_to_tree(nodes, %Node{} = node) do
    case Map.get(nodes, node.parent_id) do
      nil ->
        {:error, :not_found}

      parent ->
        nodes
        |> Map.put(node.id, node)
        |> Map.replace!(parent.id, %{parent | children_ids: [node.id | parent.children_ids]})
        |> then(&{:ok, &1})
    end
  end

  # Just for being explicit
  defp get_subtree(_, %{children_ids: []} = node), do: %{node.id => node}

  defp get_subtree(nodes, node) do
    node.children_ids
    |> Enum.reduce(%{node.id => node}, fn child_id, acc ->
      child = Map.fetch!(nodes, child_id)

      get_subtree(nodes, child)
      |> Map.merge(acc)
    end)
  end
end
