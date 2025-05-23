defmodule Unit.BeaconApiTest.V2 do
  use ExUnit.Case
  use Patch

  import Plug.Test

  alias BeaconApi.Router
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.Db
  alias Types.BlockInfo

  @moduletag :beacon_api_case
  @moduletag :tmp_dir

  @opts Router.init([])

  setup %{tmp_dir: tmp_dir} do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.merge(config: MainnetConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))

    start_link_supervised!({Db, dir: tmp_dir})
    start_supervised!(Blocks)
    :ok
  end

  test "get block by id" do
    head_root =
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0>>

    signed_block = Fixtures.Block.signed_beacon_block()
    block_id = signed_block.message.slot

    signed_block
    |> BlockInfo.from_block(head_root, :pending)
    |> BlockDb.store_block_info()

    resp_body = %{
      version: "deneb",
      execution_optimistic: true,
      finalized: false,
      data: BeaconApi.Utils.to_json(signed_block)
    }

    {:ok, encoded_resp_body_json} = Jason.encode(resp_body)

    conn =
      conn(:get, "/eth/v2/beacon/blocks/#{block_id}", nil)
      |> Router.call(@opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == encoded_resp_body_json
  end

  test "get block by hex id" do
    head_root =
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0>>

    signed_block = Fixtures.Block.signed_beacon_block()

    signed_block
    |> BlockInfo.from_block(head_root, :pending)
    |> BlockDb.store_block_info()

    resp_body = %{
      version: "deneb",
      execution_optimistic: true,
      finalized: false,
      data: BeaconApi.Utils.to_json(signed_block)
    }

    {:ok, encoded_resp_body_json} = Jason.encode(resp_body)

    hex_head_root = "0x" <> Base.encode16(head_root)

    conn =
      conn(:get, "/eth/v2/beacon/blocks/#{hex_head_root}", nil)
      |> Router.call(@opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == encoded_resp_body_json
  end
end
