defmodule BeaconApiTest do
  use ExUnit.Case
  use Plug.Test
  use Patch

  alias BeaconApi.Router
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Db

  @moduletag :beacon_api_case

  @opts Router.init([])

  setup do
    start_supervised!(Db)
    :ok
  end

  test "get block by id" do
    head_root =
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0>>

    signed_block = Fixtures.Block.signed_beacon_block()
    block_id = signed_block.message.slot
    BlockDb.store_block(signed_block, head_root)

    resp_body = %{
      version: "deneb",
      execution_optimistic: true,
      finalized: false,
      data: BeaconApi.V2.BeaconController.to_json(signed_block)
    }

    {:ok, encoded_resp_body_json} = Jason.encode(resp_body)

    conn =
      conn(:get, "/eth/v2/beacon/blocks/#{ block_id}", nil)
      |> Router.call(@opts)


    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == encoded_resp_body_json
  end
end
