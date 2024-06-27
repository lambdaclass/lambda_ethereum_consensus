defmodule Unit.BeaconApiTest.V1 do
  use ExUnit.Case
  use Plug.Test
  use Patch

  alias BeaconApi.Router
  alias BeaconApi.Utils
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Db
  alias Types.BlockInfo

  @moduletag :beacon_api_case
  @moduletag :tmp_dir

  @opts Router.init([])

  setup %{tmp_dir: tmp_dir} do
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

    start_link_supervised!({Db, dir: tmp_dir})

    patch(BeaconChain, :get_current_status_message, status_message)
    patch(ForkChoice, :get_genesis_time, 42)

    :ok
  end

  test "get state SSZ HashTreeRoot by head" do
    head_root =
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0>>

    signed_block = Fixtures.Block.signed_beacon_block()

    signed_block
    |> BlockInfo.from_block(head_root, :pending)
    |> BlockDb.store_block_info()

    expected_response = %{
      "data" => %{"root" => Utils.hex_encode(signed_block.message.state_root)},
      "finalized" => false,
      "execution_optimistic" => true
    }

    conn =
      conn(:get, "/eth/v1/beacon/states/head/root", nil)
      |> Router.call(@opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == expected_response
  end

  test "get invalid state SSZ HashTreeRoot" do
    expected_response = %{
      "code" => 400,
      "message" => "Invalid state ID: unknown_state"
    }

    conn =
      conn(:get, "/eth/v1/beacon/states/unknown_state/root", nil)
      |> Router.call(@opts)

    assert conn.state == :sent
    assert conn.status == 400
    assert Jason.decode!(conn.resp_body) == expected_response
  end

  test "get finality checkpoints by head" do
    head_root =
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0>>

    signed_block = Fixtures.Block.signed_beacon_block()

    signed_block
    |> BlockInfo.from_block(head_root, :pending)
    |> BlockDb.store_block_info()

    beacon_state = Fixtures.Block.beacon_state()

    patch(
      LambdaEthereumConsensus.Store.StateDb,
      :get_state_by_state_root,
      {:ok, beacon_state}
    )

    expected_response = %{
      "finalized" => false,
      "execution_optimistic" => true,
      "data" => %{
        "previous_justified" => %{
          "epoch" => beacon_state.previous_justified_checkpoint.epoch,
          "root" => Utils.hex_encode(beacon_state.previous_justified_checkpoint.root)
        },
        "current_justified" => %{
          "epoch" => beacon_state.current_justified_checkpoint.epoch,
          "root" => Utils.hex_encode(beacon_state.current_justified_checkpoint.root)
        },
        "finalized" => %{
          "epoch" => beacon_state.finalized_checkpoint.epoch,
          "root" => Utils.hex_encode(beacon_state.finalized_checkpoint.root)
        }
      }
    }

    conn =
      :get
      |> conn("/eth/v1/beacon/states/head/finality_checkpoints", nil)
      |> Router.call(@opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == expected_response
  end

  test "get genesis data" do
    expected_response = %{
      "data" => %{
        "genesis_time" => ForkChoice.get_genesis_time(),
        "genesis_validators_root" =>
          ChainSpec.get_genesis_validators_root() |> Utils.hex_encode(),
        "genesis_fork_version" => ChainSpec.get("GENESIS_FORK_VERSION") |> Utils.hex_encode()
      }
    }

    conn = conn(:get, "/eth/v1/beacon/genesis", nil) |> Router.call(@opts)

    assert conn.state == :sent
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == expected_response
  end

  test "node health" do
    conn = conn(:get, "/eth/v1/node/health", nil) |> Router.call(@opts)
    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == ""
  end

  test "node identity" do
    alias LambdaEthereumConsensus.Libp2pPort
    alias LambdaEthereumConsensus.P2P.Metadata
    patch(ForkChoice, :get_fork_version, fn -> ChainSpec.get("DENEB_FORK_VERSION") end)

    start_link_supervised!(Libp2pPort)
    Metadata.init()
    identity = Libp2pPort.get_node_identity()
    metadata = Metadata.get_metadata()

    expected_response = %{
      "data" => %{
        "peer_id" => identity[:pretty_peer_id],
        "enr" => identity[:enr],
        "p2p_addresses" => identity[:p2p_addresses],
        "discovery_addresses" => identity[:discovery_addresses],
        "metadata" => %{
          "seq_number" => Utils.to_json(metadata.seq_number),
          "attnets" => Utils.to_json(metadata.attnets),
          "syncnets" => Utils.to_json(metadata.syncnets)
        }
      }
    }

    conn = conn(:get, "/eth/v1/node/identity", nil) |> Router.call(@opts)
    assert conn.state == :sent
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == expected_response
  end
end
