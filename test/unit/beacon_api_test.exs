defmodule BeaconApiTest do
  use ExUnit.Case
  use Plug.Test
  use Patch
  alias BeaconApi.Router
  alias LambdaEthereumConsensus.Store.BlockStore
  alias LambdaEthereumConsensus.Store.Db

  @moduletag :beacon_api_case

  @opts Router.init([])

  setup do
    Application.put_env(:lambda_ethereum_consensus, ChainSpec, config: MainnetConfig)

    head_root =
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0>>

    status_message = %Types.StatusMessage{
      fork_digest: Fixtures.Random.binary(4),
      finalized_root: Fixtures.Random.root(),
      finalized_epoch: Fixtures.Random.uint64(),
      head_root: head_root,
      head_slot: Fixtures.Random.uint64()
    }

    start_supervised!(Db)

    patch(
      LambdaEthereumConsensus.Beacon.BeaconChain,
      :get_current_status_message,
      {:ok, status_message}
    )

    :ok
  end

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
