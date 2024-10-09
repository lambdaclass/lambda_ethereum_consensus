defmodule BeaconApi.V1.NodeController do
  use BeaconApi, :controller

  alias BeaconApi.ApiSpec
  alias BeaconApi.Utils
  alias LambdaEthereumConsensus.Beacon.SyncBlocks
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Metadata

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  # NOTE: this function is required by OpenApiSpex, and should return the information
  #  of each specific endpoint. We just return the specific entry from the parsed spec.
  def open_api_operation(:health),
    do: ApiSpec.spec().paths["/eth/v1/node/health"].get

  def open_api_operation(:identity),
    do: ApiSpec.spec().paths["/eth/v1/node/identity"].get

  def open_api_operation(:version),
    do: ApiSpec.spec().paths["/eth/v1/node/version"].get

  def open_api_operation(:syncing),
    do: ApiSpec.spec().paths["/eth/v1/node/syncing"].get

  def open_api_operation(:peers),
    do: ApiSpec.spec().paths["/eth/v1/node/peers"].get

  @spec health(Plug.Conn.t(), any) :: Plug.Conn.t()
  def health(conn, _params) do
    %{is_syncing: syncing?} = SyncBlocks.status()
    syncing_status = if syncing?, do: 206, else: 200

    send_resp(conn, syncing_status, "")
  rescue
    _ -> send_resp(conn, 503, "")
  end

  @spec identity(Plug.Conn.t(), any) :: Plug.Conn.t()
  def identity(conn, _params) do
    metadata = Metadata.get_metadata() |> Utils.to_json()

    %{
      pretty_peer_id: peer_id,
      enr: enr,
      p2p_addresses: p2p_addresses,
      discovery_addresses: discovery_addresses
    } = Libp2pPort.get_node_identity()

    conn
    |> json(%{
      "data" => %{
        "peer_id" => peer_id,
        "enr" => enr,
        "p2p_addresses" => p2p_addresses,
        "discovery_addresses" => discovery_addresses,
        "metadata" => metadata
      }
    })
  end

  @spec version(Plug.Conn.t(), any) :: Plug.Conn.t()
  def version(conn, _params) do
    version = Application.spec(:lambda_ethereum_consensus)[:vsn]
    arch = :erlang.system_info(:system_architecture)

    conn
    |> json(%{
      "data" => %{
        "version" => "Lambda/#{version}/#{arch}"
      }
    })
  end

  @spec syncing(Plug.Conn.t(), any) :: Plug.Conn.t()
  def syncing(conn, _params) do
    %{
      is_syncing: is_syncing,
      is_optimistic: is_optimistic,
      el_offline: el_offline,
      head_slot: head_slot,
      sync_distance: sync_distance
    } = SyncBlocks.status()

    json(conn, %{"data" => %{
      "is_syncing" => is_syncing,
      "is_optimistic" => is_optimistic,
      "el_offline" => el_offline,
      "head_slot" => head_slot |> Integer.to_string(),
      "sync_distance" => sync_distance |> Integer.to_string()
    }})
  end

  @spec peers(Plug.Conn.t(), any) :: Plug.Conn.t()
  def peers(conn, _params) do
    # TODO: (#1325) This is a stub.
    conn
    |> json(%{
      "data" => [%{}],
      "meta" => %{
        "count" => 0
      }
    })
  end
end
