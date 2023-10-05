defmodule LambdaEthereumConsensus.ForkChoice.Tree do
  @moduledoc """
  Fork tree. Nodes are represented as tuples. Usage:

  Tree.add_block(node)
  head = Tree.get_head()

  A node containing :root as a parent_id is considered a the root. When adding a block,
  the subtree_weight of all of its parents up until the root will be updated. At the same
  time, the head wil be recalculated using the greedy heaviest subtree strategy.

  When requesting the head, a cached value will be returned instantly, according to the last
  calculated one.
  """

  use GenServer
  require Logger

  defmodule Node do
    @moduledoc """
    A struct representing a tree node, with its id, the id from its parent and the ids from its
    children. Ids are state roots, which are 32 byte strings.

    It also contains its own self_weight due to attestations and proposer boost, and a
    subtree_weight, which is the sum of all of the weights of its successors. This value is calculated
    by the tree so manually assignment is not necessary.
    """
    defstruct [:parent_id, :id, :children_ids, :self_weight, :subtree_weight]
    @type id :: String.t()
    @type t :: %Node{
            parent_id: id | :root,
            id: id,
            children_ids: [id],
            self_weight: integer(),
            subtree_weight: integer()
          }
  end

  # Note: we might want to stop supporting nil roots and have it as an init arg.
  @type status :: %{root: Node.id() | nil, tree: %{Node.id() => Node.t()}, head: Node.t() | nil}

  ##########################
  ### Public API
  ##########################

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc """
  Adds a block to the fork-choice tree. Assumes that the parent is already present
  (unless it's the root of the tree).

  Passing a root restarts the tree structure completely. This operation is between O(logn)
  for trees that are balanced, and O(n) when there are no forks, being n the amount of blocks
  between the root and the added node.
  """
  @spec add_block(Node.t()) :: :ok
  def add_block(%Node{} = node), do: GenServer.cast(__MODULE__, {:add_block, node})

  @doc """
  Gets the head node according to LMD GHOST. The values are pre-calculated when adding nodes,
  so this operation is O(1).
  """
  @spec get_head :: Node.t()
  def get_head, do: GenServer.call(__MODULE__, :get_head)

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init(any) :: {:ok, status()}
  def init(_), do: {:ok, %{root: nil, tree: %{}, head: nil}}

  @impl GenServer
  def handle_cast({:add_block, node}, status) do
    new_tree = add_node_to_tree(status.tree, node)
    new_root = if node.parent_id == :root, do: node.id, else: status.root
    head = get_head(new_tree, new_tree[new_root])

    {:noreply, Map.merge(status, %{tree: new_tree, head: head, root: new_root})}
  end

  # TODO: We might want to cache the head (or the whole tree) in an ETS entry
  # for concurrent access.
  @impl GenServer
  def handle_call(:get_head, _from, %{head: head} = state) do
    {:reply, head, state}
  end

  ##########################
  ### Private Functions
  ##########################

  defp add_node_to_tree(tree, %Node{} = node) do
    # The subtree weight of a node is its own weight.
    node = node |> Map.put(:subtree_weight, node.self_weight)

    tree
    |> Map.put(node.id, node)
    |> update_parent(node)
    |> add_weight(node.parent_id, node.self_weight)
  end

  defp update_parent(tree, %Node{parent_id: :root}), do: tree

  defp update_parent(tree, node) do
    Map.update!(tree, node.parent_id, fn parent -> add_child_to_node(parent, node) end)
  end

  defp add_weight(tree, :root, _weight), do: tree

  defp add_weight(tree, node_id, weight) do
    node = tree[node_id]
    new_weight = weight + node.subtree_weight
    new_node = Map.put(node, :subtree_weight, new_weight)
    new_tree = Map.put(tree, node_id, new_node)
    add_weight(new_tree, new_node.parent_id, new_weight)
  end

  defp get_head(_tree, nil), do: nil
  defp get_head(_tree, %Node{children_ids: []} = node), do: node

  defp get_head(tree, node) do
    next_id = node.children_ids |> Enum.max_by(fn id -> tree[id].subtree_weight end)
    get_head(tree, tree[next_id])
  end

  defp add_child_to_node(node, child) do
    Map.update(node, :children_ids, [child.id], fn ids -> [child.id | ids] end)
  end
end
