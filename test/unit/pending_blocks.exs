defmodule PendingBlocksTest do
  use ExUnit.Case
  alias ExUnit.AssertionError
  alias Fixtures.Block
  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.BlockInfo

  use Patch

  setup %{tmp_dir: tmp_dir} do
    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    start_link_supervised!(LambdaEthereumConsensus.Store.Blocks)
    :ok
  end

  defp new_block_info() do
    Block.signed_beacon_block() |> BlockInfo.from_block()
  end

  @tag :tmp_dir
  @tag :skip
  test "Download blocks" do
    block_info = new_block_info()
    root = block_info.root

    # This now needs to send stuff to libP2P instead of returning.
    patch(BlockDownloader, :request_blocks_by_root, fn
      [^root] -> {:ok, [block_info.signed_block]}
      _else -> {:error, nil}
    end)

    Blocks.add_block_to_download(root)

    assert Blocks.get_blocks_with_status(:download) ==
             {:ok,
              [
                %BlockInfo{
                  root: root,
                  status: :download,
                  signed_block: nil
                }
              ]}

    Process.send(PendingBlocks, :download_blocks, [])
    expected_block_info = BlockInfo.change_status(block_info, :download_blobs)

    # Waits for the block to be downloaded
    assert_retry(10, 100, fn ->
      assert Blocks.get_blocks_with_status(:download) == {:ok, []}
      assert Blocks.get_blocks_with_status(:download_blobs) == {:ok, [expected_block_info]}
    end)
  end

  defp assert_retry(delay_milliseconds, retries, assertion) do
    Process.sleep(delay_milliseconds)

    try do
      assertion.()
    rescue
      e in AssertionError ->
        if retries <= 0 do
          reraise e, __STACKTRACE__
        else
          assert_retry(delay_milliseconds, retries - 1, assertion)
        end
    end
  end
end
