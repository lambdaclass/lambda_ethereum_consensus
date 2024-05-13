defmodule BeaconApi.V1.NodeController do
  use BeaconApi, :controller

  alias BeaconApi.ApiSpec
  alias BeaconApi.Utils
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Metadata

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  # NOTE: this function is required by OpenApiSpex, and should return the information
  #  of each specific endpoint. We just return the specific entry from the parsed spec.
  def open_api_operation(:health),
    do: ApiSpec.spec().paths["/eth/v1/node/health"].get

  def open_api_operation(:identity),
    do: ApiSpec.spec().paths["/eth/v1/node/identity"].get

  @spec health(Plug.Conn.t(), any) :: Plug.Conn.t()
  def health(conn, params) do
    # TODO: respond with syncing status if we're still syncing
    _syncing_status = Map.get(params, :syncing_status, 206)

    send_resp(conn, 200, "")
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
end
