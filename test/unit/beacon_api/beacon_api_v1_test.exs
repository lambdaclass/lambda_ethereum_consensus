defmodule Unit.BeaconApiTest.V1 do
  use ExUnit.Case
  use Plug.Test
  use Patch

  alias BeaconApi.Router
  alias BeaconApi.Utils
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Db

  @moduletag :beacon_api_case

  @opts Router.init([])

  setup do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.merge(config: MainnetConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))

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

    patch(BeaconChain, :get_current_status_message, {:ok, status_message})
    patch(BeaconChain, :get_genesis_time, 42)

    :ok
  end

  test "get state SSZ HashTreeRoot by head" do
    head_root =
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0>>

    signed_block = Fixtures.Block.signed_beacon_block()
    BlockDb.store_block(signed_block, head_root)

    resp_body = %{
      data: %{root: Utils.hex_encode(signed_block.message.state_root)},
      finalized: false,
      execution_optimistic: true
    }

    {:ok, encoded_resp_body_json} = Jason.encode(resp_body)

    conn =
      conn(:get, "/eth/v1/beacon/states/head/root", nil)
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
      conn(:get, "/eth/v1/beacon/states/unknown_state/root", nil)
      |> Router.call(@opts)

    assert conn.state == :sent
    assert conn.status == 400
    assert conn.resp_body == encoded_resp_body_json
  end

  test "get finality checkpoints by head" do
    head_root =
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0>>

    signed_block = Fixtures.Block.signed_beacon_block()
    BlockDb.store_block(signed_block, head_root)
    beacon_state = Fixtures.Block.beacon_state()

    patch(
      LambdaEthereumConsensus.Store.StateDb,
      :get_state_by_state_root,
      {:ok, beacon_state}
    )

    resp_body = %{
      finalized: false,
      execution_optimistic: true,
      data: %{
        previous_justified: %{
          epoch: beacon_state.previous_justified_checkpoint.epoch,
          root: Utils.hex_encode(beacon_state.previous_justified_checkpoint.root)
        },
        current_justified: %{
          epoch: beacon_state.current_justified_checkpoint.epoch,
          root: Utils.hex_encode(beacon_state.current_justified_checkpoint.root)
        },
        finalized: %{
          epoch: beacon_state.finalized_checkpoint.epoch,
          root: Utils.hex_encode(beacon_state.finalized_checkpoint.root)
        }
      }
    }

    {:ok, encoded_resp_body_json} = Jason.encode(resp_body)

    conn =
      :get
      |> conn("/eth/v1/beacon/states/head/finality_checkpoints", nil)
      |> Router.call(@opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == encoded_resp_body_json
  end

  test "get genesis data" do
    {:ok, expected_body} =
      Jason.encode(%{
        "data" => %{
          "genesis_time" => BeaconChain.get_genesis_time(),
          "genesis_validators_root" =>
            ChainSpec.get_genesis_validators_root() |> Utils.hex_encode(),
          "genesis_fork_version" => ChainSpec.get("GENESIS_FORK_VERSION") |> Utils.hex_encode()
        }
      })

    conn = conn(:get, "/eth/v1/beacon/genesis", nil) |> Router.call(@opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == expected_body
  end
end
