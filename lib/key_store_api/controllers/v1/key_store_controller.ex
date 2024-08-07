defmodule KeyStoreApi.V1.KeyStoreController do
  use KeyStoreApi, :controller

  alias BeaconApi.Utils
  alias KeyStoreApi.ApiSpec
  alias LambdaEthereumConsensus.Libp2pPort

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
    conn
    |> json(%{
      "data" =>
        Libp2pPort.get_keystores()
        |> Enum.map(
          &%{
            "validatin_pubkey" => &1.pubkey |> Utils.hex_encode(),
            "derivation_path" => &1.path,
            "readonly" => &1.readonly
          }
        )
    })
  end

  @spec add_keys(Plug.Conn.t(), any) :: Plug.Conn.t()
  def add_keys(conn, _params) do
    body_params = conn.private.open_api_spex.body_params

    config =
      Application.get_env(:lambda_ethereum_consensus, LambdaEthereumConsensus.Validator.Setup, [])

    keystore_dir = Keyword.get(config, :keystore_dir) || @default_keystore_dir
    keystore_pass_dir = Keyword.get(config, :keystore_pass_dir) || @default_keystore_pass_dir

    results =
      Enum.zip(body_params.keystores, body_params.passwords)
      |> Enum.map(fn {keystore_file, password_file} ->
        keystore = Keystore.decode_str!(keystore_file, password_file)

        File.write!(
          Path.join(
            keystore_dir,
            "#{inspect(keystore.pubkey |> Utils.hex_encode())}.json"
          ),
          keystore_file
        )

        File.write!(
          Path.join(
            keystore_pass_dir,
            "#{inspect(keystore.pubkey |> Utils.hex_encode())}.txt"
          ),
          password_file
        )

        %{
          status: "imported",
          message: "Pubkey: #{inspect(keystore.pubkey)}"
        }
      end)

    conn
    |> json(%{
      "data" => results
    })
  end
end
