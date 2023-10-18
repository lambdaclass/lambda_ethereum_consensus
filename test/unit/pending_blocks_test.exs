defmodule Unit.PendingBlocks do
  use ExUnit.Case, async: true
  use Patch

  alias LambdaEthereumConsensus.ForkChoice.Store
  alias LambdaEthereumConsensus.Beacon.PendingBlocks

  setup do
    # Lets trigger the process_blocks manually
    patch(PendingBlocks, :schedule_blocks_processing, fn -> :ok end)

    start_supervised!({PendingBlocks, ["host"]})
    :ok
  end

  test "Adds a pending block to fork choice if the parent is there" do
    block = Fixtures.Block.beacon_block()
    {:ok, block_root} = Ssz.hash_tree_root(block)

    patch(Store, :has_block?, fn root -> root == block.parent_root end)

    PendingBlocks.add_block(block)

    assert PendingBlocks.is_pending_block(block_root)
    send(PendingBlocks, :process_blocks)

    # If the block is not pending anymore, it means it was added to the fork choice
    assert not PendingBlocks.is_pending_block(block_root)
  end
end
