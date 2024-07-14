defmodule Unit.Store.BlockDbTest do
  alias Fixtures.Block
  alias LambdaEthereumConsensus.Store.BlockBySlot
  alias LambdaEthereumConsensus.Store.BlockDb

  use ExUnit.Case

  setup %{tmp_dir: tmp_dir} do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.put(:config, MainnetConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))

    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    :ok
  end

  @tag :tmp_dir
  test "Simple block saving and loading" do
    block_info = Block.block_info()
    BlockDb.store_block_info(block_info)
    assert {:ok, block_info} == BlockDb.get_block_info(block_info.root)
  end

  @tag :tmp_dir
  test "A saved block's root can be retrieved using its slot" do
    block_info = Block.block_info()
    BlockDb.store_block_info(block_info)

    assert {:ok, block_info} ==
             BlockDb.get_block_info_by_slot(block_info.signed_block.message.slot)
  end

  @tag :tmp_dir
  test "Pruning deletes only blocks prior to the one selected as target" do
    blocks =
      [block_1, block_2, block_3] =
      [Block.block_info(), Block.block_info(), Block.block_info()]
      |> Enum.sort_by(& &1.signed_block.message.slot)

    Enum.each(blocks, &BlockDb.store_block_info/1)

    assert {:ok, block_1} == BlockDb.get_block_info(block_1.root)
    assert {:ok, block_2} == BlockDb.get_block_info(block_2.root)
    assert {:ok, block_3} == BlockDb.get_block_info(block_3.root)

    BlockDb.prune_blocks_older_than(block_2.signed_block.message.slot)

    assert :not_found == BlockDb.get_block_info(block_1.root)
    assert {:ok, block_2} == BlockDb.get_block_info(block_2.root)
    assert {:ok, block_3} == BlockDb.get_block_info(block_3.root)
  end

  @tag :tmp_dir
  test "Pruning on a non existent root returns and doesn't delete anything" do
    blocks =
      [block_1, block_2, block_3] =
      [Block.block_info(), Block.block_info(), Block.block_info()]
      |> Enum.sort_by(& &1.signed_block.message.slot)

    Enum.each(blocks, &BlockDb.store_block_info/1)

    random_slot = (blocks |> Enum.map(& &1.signed_block.message.slot) |> Enum.max()) + 1
    assert :ok == BlockDb.prune_blocks_older_than(random_slot)
    assert {:ok, block_1} == BlockDb.get_block_info(block_1.root)
    assert {:ok, block_2} == BlockDb.get_block_info(block_2.root)
    assert {:ok, block_3} == BlockDb.get_block_info(block_3.root)
  end

  @tag :tmp_dir
  test "Empty blocks don't affect pruning" do
    blocks =
      [block_1, block_2, block_3] =
      [Block.block_info(), Block.block_info(), Block.block_info()]
      |> Enum.sort_by(& &1.signed_block.message.slot)

    Enum.each(blocks, &BlockDb.store_block_info/1)

    block_slots = Enum.map(blocks, & &1.signed_block.message.slot)

    min_slot = Enum.min(block_slots) - 1
    max_slot = Enum.max(block_slots) + 1
    BlockBySlot.put(max_slot, :empty_slot)
    BlockBySlot.put(min_slot, :empty_slot)

    assert :ok == BlockDb.prune_blocks_older_than(max_slot)
    assert :not_found == BlockDb.get_block_info(block_1.root)
    assert :not_found == BlockDb.get_block_info(block_2.root)
    assert :not_found == BlockDb.get_block_info(block_3.root)
    assert {:ok, :empty_slot} == BlockBySlot.get(max_slot)
    assert :not_found == BlockBySlot.get(min_slot)
  end
end
