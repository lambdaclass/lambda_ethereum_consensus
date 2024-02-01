defmodule BeaconApiTest do
  use ExUnit.Case
  use Plug.Test
  use Patch
  alias BeaconApi.Router
  alias LambdaEthereumConsensus.Store.BlockStore

  @moduletag :beacon_api_case

  @opts Router.init([])

  test "get state SSZ HashTreeRoot by head" do
    head_root =
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0>>

    signed_block = Fixtures.Block.signed_beacon_block()
    BlockStore.store_block(signed_block, head_root)

    resp_body = %{
      data: %{root: "0x" <> Base.encode16(signed_block.message.state_root, case: :lower)},
      finalized: false,
      execution_optimistic: true
    }

    {:ok, encoded_resp_body_json} = Jason.encode(resp_body)

    conn =
      :get
      |> conn("/eth/v1/beacon/states/head/root", nil)
      |> Router.call(@opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == encoded_resp_body_json
  end

  test "get invalid state SSZ HashTreeRoot" do
    resp_body = %{
      code: 400,
      message: "Invalid state ID: unknown_state"
    }

    {:ok, encoded_resp_body_json} = Jason.encode(resp_body)

    conn =
      :get
      |> conn("/eth/v1/beacon/states/unknown_state/root", nil)
      |> Router.call(@opts)

    assert conn.state == :sent
    assert conn.status == 400
    assert conn.resp_body == encoded_resp_body_json
  end
end
