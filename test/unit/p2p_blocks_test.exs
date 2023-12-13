defmodule Unit.P2PBlocks do
  use ExUnit.Case, async: true
  use Patch

  alias LambdaEthereumConsensus.Store.BlockStore
  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.IncomingRequests.Handler
  alias SszTypes.BeaconBlocksByRootRequest
  alias LambdaEthereumConsensus.Store.Db

  setup do
    expose(Handler, :all)
    start_supervised!(Db)
    :ok
  end

  test "one block retrieve" do
    #
    signed_block_input = Fixtures.Block.signed_beacon_block()
    block_root = Ssz.hash_tree_root!(signed_block_input.message)

    # store the block in the BlockStore
    BlockStore.store_block(signed_block_input)

    # ssz serialize and snappy compress the block root
    with {:ok, ssz_serialized} <- Ssz.to_ssz(BeaconBlocksByRootRequest{body: [block_root]}),
         {:ok, snappy_compressed_message} <- Snappy.compress(ssz_serialized) do
      # patch the Libp2pPort's send_request function to call the incoming_requests handler function we want to test
      patch(Libp2pPort, :send_request, fn _peer_id, _protocol, message ->
        Handler.handle("beacon_blocks_by_root/2/ssz_snappy", 1, message)
      end)

      patch(Libp2pPort, :send_response, fn _request_id, message -> :ok end)

      # call the block_downloader's request_blocks_by_root function
      with {:ok, signed_beacon_blocks} <- BlockDownloader.request_blocks_by_root([block_root]) do
        assert Enum.at(signed_beacon_blocks, 0) == signed_block_input
      end
    end
  end
end
