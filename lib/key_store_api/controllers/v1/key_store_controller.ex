defmodule KeyStoreApi.V1.KeyStoreController do
  use KeyStoreApi, :controller

  alias BeaconApi.Utils
  alias KeyStoreApi.ApiSpec
  alias LambdaEthereumConsensus.Validator.ValidatorManager

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  # NOTE: this function is required by OpenApiSpex, and should return the information
  #  of each specific endpoint. We just return the specific entry from the parsed spec.
  def open_api_operation(:get_keys),
    do: ApiSpec.spec().paths["/eth/v1/keystores"].get

  @spec get_keys(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_keys(conn, _params) do
    pubkeys_info =
      ValidatorManager.get_pubkeys()
      |> Enum.map(
        &%{
          "validatin_pubkey" => &1 |> Utils.hex_encode(),
          "derivation_path" => "m/12381/3600/0/0/0",
          "readonly" => true
        }
      )

    conn
    |> json(%{
      "data" => pubkeys_info
    })
  end
end
