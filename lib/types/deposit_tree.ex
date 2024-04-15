defmodule Types.DepositTree do
  @moduledoc """
  Pruned Merkle tree, for use in block production.
  Implementation adapted from [EIP-4881](https://eips.ethereum.org/EIPS/eip-4881).
  """
  alias Types.Deposit
  alias Types.DepositData
  alias Types.DepositTreeSnapshot
  alias Types.Eth1Data

  @tree_depth Constants.deposit_contract_tree_depth()

  defstruct inner: {:zero, @tree_depth},
            deposit_count: 0,
            finalized_execution_block: nil

  @type leaf :: {:leaf, {Types.hash32(), DepositData.t()}}
  @type summary :: {:zero, non_neg_integer()} | {:finalized, {Types.hash32(), non_neg_integer()}}
  @type tree_node :: leaf() | summary() | {:node, {tree_node(), tree_node()}}

  @type proof :: [Types.root()]

  @type t :: %__MODULE__{
          inner: tree_node(),
          deposit_count: non_neg_integer(),
          finalized_execution_block: {Types.hash32(), non_neg_integer()} | nil
        }

  ################
  ## Public API ##
  ################

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec from_snapshot(DepositTreeSnapshot.t()) :: t()
  def from_snapshot(%DepositTreeSnapshot{} = snapshot) do
    inner_tree = from_snapshot_parts(snapshot.finalized, snapshot.deposit_count, @tree_depth)
    execution_info = {snapshot.execution_block_hash, snapshot.execution_block_height}

    %__MODULE__{
      inner: inner_tree,
      deposit_count: snapshot.deposit_count,
      finalized_execution_block: execution_info
    }
  end

  @spec finalize(t(), Eth1Data.t(), non_neg_integer()) :: t()
  def finalize(%__MODULE__{} = tree, %Eth1Data{} = eth1_data, execution_block_height) do
    finalized_block = {eth1_data.block_hash, execution_block_height}
    new_inner = finalize_tree(tree.inner, eth1_data.deposit_count, 2 ** @tree_depth)
    %{tree | inner: new_inner, finalized_execution_block: finalized_block}
  end

  @spec get_deposit(t(), non_neg_integer()) :: {:ok, Deposit.t()} | {:error, String.t()}
  def get_deposit(%__MODULE__{} = tree, index) do
    cond do
      index < get_finalized(tree.inner) ->
        {:error, "deposit already finalized"}

      index >= tree.deposit_count ->
        {:error, "deposit index out of bounds"}

      true ->
        {data, proof} = generate_proof(tree.inner, index, @tree_depth, [mix_in_length(tree)])
        {:ok, %Deposit{proof: proof, data: data}}
    end
  end

  @spec get_root(t()) :: Types.root()
  def get_root(%__MODULE__{inner: inner} = tree),
    do: SszEx.hash_nodes(get_node_root(inner), mix_in_length(tree))

  @spec get_deposit_count(t()) :: non_neg_integer()
  def get_deposit_count(%__MODULE__{deposit_count: count}), do: count

  @spec push_leaf(t(), DepositData.t()) :: t()
  def push_leaf(%__MODULE__{} = tree, %DepositData{} = deposit) do
    leaf = {SszEx.hash_tree_root!(deposit), deposit}
    new_inner = push_leaf_inner(tree.inner, leaf, @tree_depth)
    %{tree | inner: new_inner, deposit_count: tree.deposit_count + 1}
  end

  #######################
  ## Private functions ##
  #######################

  # Empty tree
  defp from_snapshot_parts([], 0, level), do: {:zero, level}

  defp from_snapshot_parts([head | rest] = finalized, deposit_count, level) do
    left_subtree = 2 ** (level - 1)

    cond do
      deposit_count == 2 ** level ->
        {:finalized, {head, deposit_count}}

      deposit_count <= left_subtree ->
        left = from_snapshot_parts(finalized, deposit_count, level - 1)
        right = {:zero, level - 1}
        {:node, {left, right}}

      true ->
        left = {:finalized, {head, left_subtree}}
        right = from_snapshot_parts(rest, deposit_count - left_subtree, level - 1)
        {:node, {left, right}}
    end
  end

  defp create_node([], depth), do: {:zero, depth}
  defp create_node([leaf | _], 0), do: {:leaf, leaf}

  defp create_node(leaves, depth) do
    {leaves_left, leaves_right} = Enum.split(leaves, 2 ** (depth - 1))
    {:node, {create_node(leaves_left, depth - 1), create_node(leaves_right, depth - 1)}}
  end

  defp finalize_tree({:finalized, _} = node, _, _), do: node
  defp finalize_tree({:leaf, {hash, _}}, _, _), do: {:finalized, {hash, 1}}

  defp finalize_tree({:node, _} = node, to_finalize, deposits) when deposits <= to_finalize,
    do: {:finalized, {get_node_root(node), deposits}}

  defp finalize_tree({:node, {left, right}}, to_finalize, deposits) do
    child_deposits = div(deposits, 2)
    new_left = finalize_tree(left, to_finalize, child_deposits)

    new_right =
      if to_finalize > child_deposits,
        do: finalize_tree(right, to_finalize - child_deposits, child_deposits),
        else: right

    {:node, {new_left, new_right}}
  end

  @spec generate_proof(tree_node(), non_neg_integer(), non_neg_integer(), list()) ::
          {DepositData.t(), proof()}
  defp generate_proof({:leaf, {_, deposit_data}}, _, 0, proof), do: {deposit_data, proof}

  defp generate_proof({:node, {left, right}}, index, depth, proof) do
    ith_bit = Bitwise.bsr(index, depth - 1) |> Bitwise.band(0x1)

    {a, b} = if ith_bit == 1, do: {right, left}, else: {left, right}

    generate_proof(a, index, depth - 1, [get_node_root(b) | proof])
  end

  defp get_node_root({:zero, level}), do: SszEx.get_zero_hash(level)
  defp get_node_root({:finalized, {hash, _}}), do: hash

  defp get_node_root({:node, {left, right}}),
    do: SszEx.hash_nodes(get_node_root(left), get_node_root(right))

  defp get_node_root({:leaf, {hash, _}}), do: hash

  defp push_leaf_inner({:node, {left, right}}, leaf_value, level) do
    if full?(left) do
      new_right = push_leaf_inner(right, leaf_value, level - 1)
      {:node, {left, new_right}}
    else
      new_left = push_leaf_inner(left, leaf_value, level - 1)
      {:node, {new_left, right}}
    end
  end

  defp push_leaf_inner({:zero, level}, leaf_value, level) do
    create_node([leaf_value], level)
  end

  defp full?({:node, {_, right}}), do: full?(right)
  defp full?({:zero, _}), do: false
  defp full?(_), do: true

  defp get_finalized({:finalized, {_, count}}), do: count
  defp get_finalized({:node, {left, right}}), do: get_finalized(left) + get_finalized(right)
  defp get_finalized({:leaf, _}), do: 0
  defp get_finalized({:zero, _}), do: 0

  defp mix_in_length(%__MODULE__{deposit_count: count}),
    do: SszEx.hash_tree_root!(count, TypeAliases.uint64())
end
