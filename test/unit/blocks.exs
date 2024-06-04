defmodule BlocksTest do
  use ExUnit.Case
  alias Fixtures.Block
  alias LambdaEthereumConsensus.Store.BlockDb.BlockInfo
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.BeaconBlock

  setup %{tmp_dir: tmp_dir} do
    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    start_link_supervised!(LambdaEthereumConsensus.Store.Blocks)
    :ok
  end

  @tag :tmp_dir
  test "Block info construction correctly calculates the root." do
    block_info = BlockInfo.from_block(Block.signed_beacon_block())

    assert {:ok, block_info.root} ==
             Ssz.hash_tree_root(block_info.signed_block.message, BeaconBlock)
  end

  @tag :tmp_dir
  test "Basic block saving and loading" do
    block_info = BlockInfo.from_block(Block.signed_beacon_block())
    assert Blocks.get_block(block_info.root) == nil
    Blocks.new_block_info(block_info)
    assert block_info == Blocks.get_block_info(block_info.root)
  end

  @tag :tmp_dir
  test "Status is updated correctly when changing the status" do
    assert {:ok, []} == Blocks.get_blocks_with_status(:pending)
    block_info = BlockInfo.from_block(Block.signed_beacon_block())

    Blocks.new_block_info(block_info)
    assert {:ok, [block_info]} == Blocks.get_blocks_with_status(:pending)

    Blocks.change_status(block_info, :invalid)
    expected_block = BlockInfo.change_status(block_info, :invalid)
    assert {:ok, []} == Blocks.get_blocks_with_status(:pending)
    assert Blocks.get_block_info(block_info.root) == expected_block
    assert {:ok, [expected_block]} == Blocks.get_blocks_with_status(:invalid)
  end
end
