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
    _node_identity = Libp2pPort.get_node_identity()

    _example = %{
      data: %{
        peer_id: "QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N",
        enr:
          "enr:-IS4QHCYrYZbAKWCBRlAy5zzaDZXJBGkcnh4MHcBFZntXNFrdvJjX04jRzjzCBOonrkTfj499SZuOh8R33Ls8RRcy5wBgmlkgnY0gmlwhH8AAAGJc2VjcDI1NmsxoQPKY0yuDUmstAHYpMa2_oxVtw0RW_QAdpzBQA8yWM0xOIN1ZHCCdl8",
        p2p_addresses: [
          "/ip4/7.7.7.7/tcp/4242/p2p/QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N"
        ],
        discovery_addresses: [
          "/ip4/7.7.7.7/udp/30303/p2p/QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N"
        ],
        metadata: %{
          seq_number: "1",
          attnets: "0x0000000000000000",
          syncnets: "0x0f"
        }
      }
    }

    conn
    |> json(%{
      data: %{
        peer_id: "QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N",
        enr:
          "enr:-IS4QHCYrYZbAKWCBRlAy5zzaDZXJBGkcnh4MHcBFZntXNFrdvJjX04jRzjzCBOonrkTfj499SZuOh8R33Ls8RRcy5wBgmlkgnY0gmlwhH8AAAGJc2VjcDI1NmsxoQPKY0yuDUmstAHYpMa2_oxVtw0RW_QAdpzBQA8yWM0xOIN1ZHCCdl8",
        p2p_addresses: [
          "/ip4/7.7.7.7/tcp/4242/p2p/QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N"
        ],
        discovery_addresses: [
          "/ip4/7.7.7.7/udp/30303/p2p/QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N"
        ],
        metadata: metadata
      }
    })
  end
end
