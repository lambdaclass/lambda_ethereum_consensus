defmodule PendingBlocksTest do
  use ExUnit.Case
  alias Fixtures.Block
  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.BlockInfo

  use Patch

  setup %{tmp_dir: tmp_dir} do
    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    start_link_supervised!(LambdaEthereumConsensus.Store.Blocks)
    start_link_supervised!(LambdaEthereumConsensus.Beacon.PendingBlocks)
    :ok
  end

  defp new_block_info() do
    Block.signed_beacon_block() |> BlockInfo.from_block()
  end

  @tag :tmp_dir
  test "Download blocks" do
    block_info = new_block_info()
    Blocks.add_block_to_download(block_info.root)

    assert Blocks.get_blocks_with_status(:download) ==
             {:ok,
              [
                %BlockInfo{
                  root: block_info.root,
                  status: :download,
                  signed_block: nil
                }
              ]}

    patch(BlockDownloader, :request_blocks_by_root, fn root ->
      if root == [block_info.root] do
        {:ok, [block_info.signed_block]}
      else
        {:error, nil}
      end
    end)

    Process.send(PendingBlocks, :download_blocks, [])

    # Waits for the block to be downloaded
    Process.sleep(100)

    expected_block_info = BlockInfo.change_status(block_info, :download_blobs)

    assert Blocks.get_blocks_with_status(:download) == {:ok, []}
    assert Blocks.get_blocks_with_status(:download_blobs) == {:ok, [expected_block_info]}
  end
end
