defmodule KeyStoreApi.V1.KeyStoreController do
  use KeyStoreApi, :controller

  alias BeaconApi.Utils
  alias KeyStoreApi.ApiSpec
  alias LambdaEthereumConsensus.Validator.ValidatorManager

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @default_keystore_dir "keystore_dir"
  @default_keystore_pass_dir "keystore_pass_dir"

  # NOTE: this function is required by OpenApiSpex, and should return the information
  #  of each specific endpoint. We just return the specific entry from the parsed spec.
  def open_api_operation(:get_keys),
    do: ApiSpec.spec().paths["/eth/v1/keystores"].get

  def open_api_operation(:add_keys),
    do: ApiSpec.spec().paths["/eth/v1/keystores"].post

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

  @spec add_keys(Plug.Conn.t(), any) :: Plug.Conn.t()
  def add_keys(conn, _params) do
    body_params = conn.private.open_api_spex.body_params
    config = Application.get_env(:lambda_ethereum_consensus, ValidatorManager, [])
    keystore_dir = Keyword.get(config, :keystore_dir) || @default_keystore_dir
    keystore_pass_dir = Keyword.get(config, :keystore_pass_dir) || @default_keystore_pass_dir

    results =
      Enum.zip(body_params.keystores, body_params.passwords)
      |> Enum.map(fn {keystore, password} ->
        {pubkey, _privkey} = Keystore.decode_str!(keystore, password)

        File.write!(
          Path.join(
            keystore_dir,
            "#{inspect(pubkey |> Utils.hex_encode())}.json"
          ),
          keystore
        )

        File.write!(
          Path.join(
            keystore_pass_dir,
            "#{inspect(pubkey |> Utils.hex_encode())}.txt"
          ),
          password
        )

        %{
          status: "imported",
          message: "Pubkey: #{inspect(pubkey)}"
        }
      end)

    conn
    |> json(%{
      "data" => results
    })
  end
end
