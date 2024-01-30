defmodule BeaconApiTest do
  use ExUnit.Case
  use Plug.Test
  use Patch
  alias BeaconApi.Router

  @moduletag :beacon_api_case

  @opts Router.init([])

  test "get state SSZ HashTreeRoot by head" do
    root = Fixtures.Random.root()

    resp_body = %{
      data: %{root: "0x" <> Base.encode16(root, case: :lower)},
      finalized: false,
      execution_optimistic: true
    }

    {:ok, encoded_resp_body_json} = Jason.encode(resp_body)

    patch(
      LambdaEthereumConsensus.ForkChoice.Helpers,
      :state_root_by_id,
      {:ok, {root, true, false}}
    )

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
