defmodule BlocksTest do
  use ExUnit.Case
  alias Fixtures.Block
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.BeaconBlock
  alias Types.BlockInfo

  setup %{tmp_dir: tmp_dir} do
    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    start_link_supervised!(LambdaEthereumConsensus.Store.Blocks)
    :ok
  end

  @tag :tmp_dir
  test "Block info construction correctly calculates the root." do
    block_info = new_block_info()

    assert {:ok, block_info.root} ==
             Ssz.hash_tree_root(block_info.signed_block.message, BeaconBlock)
  end

  @tag :tmp_dir
  test "Basic block saving and loading" do
    block_info = new_block_info()
    assert Blocks.get_block(block_info.root) == nil
    Blocks.new_block_info(block_info)
    assert block_info == Blocks.get_block_info(block_info.root)
  end

  @tag :tmp_dir
  test "Status is updated correctly when changing the status" do
    assert {:ok, []} == Blocks.get_blocks_with_status(:pending)
    block_info = new_block_info()

    Blocks.new_block_info(block_info)

    assert {:ok, [block_info]} == Blocks.get_blocks_with_status(:pending)

    Blocks.change_status(block_info, :invalid)
    expected_block = BlockInfo.change_status(block_info, :invalid)
    assert {:ok, []} == Blocks.get_blocks_with_status(:pending)
    assert Blocks.get_block_info(block_info.root) == expected_block
    assert {:ok, [expected_block]} == Blocks.get_blocks_with_status(:invalid)
  end

  @tag :tmp_dir
  test "Status change when multiple statuses are present" do
    block_1 = new_block_info()
    block_2 = new_block_info()
    block_3 = new_block_info()
    Blocks.new_block_info(block_1)
    Blocks.new_block_info(block_2)
    Blocks.new_block_info(block_3)

    check_status([block_1, block_2, block_3], :pending)

    Blocks.change_status(block_1, :transitioned)
    Blocks.change_status(block_2, :download_blobs)
    check_status([Map.put(block_1, :status, :transitioned)], :transitioned)
    check_status([Map.put(block_2, :status, :download_blobs)], :download_blobs)
    check_status([block_3], :pending)
  end

  @tag :tmp_dir
  test "A nil block can be saved" do
    Blocks.add_block_to_download("some_root")
    {:ok, [block]} = Blocks.get_blocks_with_status(:download)
    assert block == %BlockInfo{status: :download, root: "some_root", signed_block: nil}
    assert Blocks.get_block_info("some_root").signed_block == nil
  end

  defp new_block_info() do
    Block.signed_beacon_block() |> BlockInfo.from_block()
  end

  defp check_status(blocks, status) do
    {:ok, loaded_blocks} = Blocks.get_blocks_with_status(status)
    assert sort_by_slot(loaded_blocks) == sort_by_slot(blocks)
  end

  defp sort_by_slot(blocks) do
    Enum.sort_by(blocks, fn b -> b.signed_block.message.slot end)
  end
end
