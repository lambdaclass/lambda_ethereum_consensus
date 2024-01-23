defmodule LambdaEthereumConsensus.ForkChoice.Simple.Tree do
  @moduledoc false

  defmodule Node do
    @moduledoc false
    defstruct [:parent_id, :id, :children_ids]
    @type id :: Types.root()
    @type parent_id :: id() | :root
    @type t :: %__MODULE__{
            parent_id: parent_id(),
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
    root_node = %Node{parent_id: :root, children_ids: []}
    %__MODULE__{root: root, nodes: %{root => root_node}}
  end

  @spec add_block(t(), Node.id(), Node.id()) :: {:ok, t()} | {:error, :not_found}
  def add_block(%__MODULE__{} = tree, block_root, parent_root)
      when is_binary(block_root) and is_binary(parent_root) do
    node = %Node{
      parent_id: parent_root,
      children_ids: []
    }

    with {:ok, new_nodes} <- add_node_to_tree(tree.nodes, block_root, node) do
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
  def update_root(%__MODULE__{root: root} = tree, root), do: {:ok, tree}

  def update_root(%__MODULE__{nodes: nodes}, new_root) do
    case Map.get(nodes, new_root) do
      nil ->
        {:error, :not_found}

      node ->
        get_subtree(nodes, new_root, %{node | parent_id: :root})
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

  @spec get_children(t(), Node.id()) :: {:ok, [Node.id()]} | {:error, :not_found}
  def get_children(%__MODULE__{nodes: nodes}, parent_id) do
    case Map.get(nodes, parent_id) do
      nil -> {:error, :not_found}
      %{children_ids: ids} -> {:ok, ids}
    end
  end

  @spec get_children!(t(), Node.id()) :: [Node.id()]
  def get_children!(tree, parent_id) do
    case get_children(tree, parent_id) do
      {:error, :not_found} -> raise "Parent #{Base.encode16(parent_id)} not found in tree"
      {:ok, res} -> res
    end
  end

  @spec has_block?(t(), Node.id()) :: boolean()
  def has_block?(tree, block_root), do: Map.has_key?(tree.nodes, block_root)

  ##########################
  ### Private Functions
  ##########################

  defp add_node_to_tree(nodes, block_root, %Node{parent_id: parent_id} = node) do
    case Map.get(nodes, parent_id) do
      nil ->
        {:error, :not_found}

      parent ->
        nodes
        |> Map.put(block_root, node)
        |> Map.replace!(parent_id, %{parent | children_ids: [block_root | parent.children_ids]})
        |> then(&{:ok, &1})
    end
  end

  # Just for being explicit
  defp get_subtree(_, id, %{children_ids: []} = node), do: %{id => node}

  defp get_subtree(nodes, id, node) do
    node.children_ids
    |> Enum.reduce(%{id => node}, fn child_id, acc ->
      child = Map.fetch!(nodes, child_id)

      get_subtree(nodes, child_id, child)
      |> Map.merge(acc)
    end)
  end
end
