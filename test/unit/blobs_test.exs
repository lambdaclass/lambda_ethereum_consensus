defmodule Unit.BlobsTest do
  use ExUnit.Case
  alias Fixtures.Block
  alias LambdaEthereumConsensus.Store.BlobDb
  alias LambdaEthereumConsensus.Store.Blobs
  alias SpecTestUtils
  alias Types.BlobSidecar
  alias Types.BlockInfo

  setup %{tmp_dir: tmp_dir} do
    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    start_link_supervised!(LambdaEthereumConsensus.Store.Blocks)

    # Blob sidecar from spec test
    blob_sidecar =
      SpecTestUtils.read_ssz_from_file!(
        "test/fixtures/blobs/blob_sidecar.ssz_snappy",
        BlobSidecar
      )

    {:ok, blob_sidecar: blob_sidecar}
  end

  defp new_block_info() do
    Block.signed_beacon_block() |> BlockInfo.from_block()
  end

  describe "Blobs unit tests" do
    @tag :tmp_dir
    test "Basic blobs saving and loading", %{blob_sidecar: blob_sidecar} do
      Blobs.add_blob(blob_sidecar)
      block_root = Ssz.hash_tree_root!(blob_sidecar.signed_block_header.message)
      index = blob_sidecar.index
      {:ok, recovered_blob} = BlobDb.get_blob_sidecar(block_root, index)

      assert(blob_sidecar == recovered_blob)
    end

    @tag :tmp_dir
    test "One missing blob from block, then add, then no missing blobs", %{
      blob_sidecar: blob_sidecar
    } do
      blob_sidecar = %BlobSidecar{blob_sidecar | index: 0}

      # Create random block info
      block_info = new_block_info()
      # add blob_sidecar kzg_commitment to the block_info
      block_info =
        put_in(
          block_info.signed_block.message.body.blob_kzg_commitments,
          [blob_sidecar.kzg_commitment]
        )

      # change block root to the one from the blob
      block_info = %BlockInfo{
        block_info
        | root: Ssz.hash_tree_root!(blob_sidecar.signed_block_header.message)
      }

      # check that the blob is detetected as missing
      missing = Blobs.missing_for_block(block_info)
      assert(length(missing) == 1)
      # add blob to db
      Blobs.add_blob(blob_sidecar)
      # check that the blob is not missing
      missing = Blobs.missing_for_block(block_info)
      assert(Enum.empty?(missing))
    end
  end
end
