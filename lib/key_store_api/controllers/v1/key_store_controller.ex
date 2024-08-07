defmodule KeyStoreApi.V1.KeyStoreController do
  use KeyStoreApi, :controller

  alias BeaconApi.Utils
  alias KeyStoreApi.ApiSpec
  alias LambdaEthereumConsensus.Libp2pPort

  require Logger

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @default_keystore_dir "keystore_dir"
  @default_keystore_pass_dir "keystore_pass_dir"

  # NOTE: this function is required by OpenApiSpex, and should return the information
  #  of each specific endpoint. We just return the specific entry from the parsed spec.
  def open_api_operation(:get_keys),
    do: ApiSpec.spec().paths["/eth/v1/keystores"].get

  def open_api_operation(:add_keys),
    do: ApiSpec.spec().paths["/eth/v1/keystores"].post

  def open_api_operation(:delete_keys),
    do: ApiSpec.spec().paths["/eth/v1/keystores"].delete

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

        base_name = keystore.pubkey |> Utils.hex_encode()

        File.write!(
          Path.join(
            keystore_dir,
            base_name <> ".json"
          ),
          keystore_file
        )

        File.write!(
          Path.join(
            keystore_pass_dir,
            base_name <> ".txt"
          ),
          password_file
        )

        Libp2pPort.add_validator(keystore)

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

  @spec delete_keys(Plug.Conn.t(), any) :: Plug.Conn.t()
  def delete_keys(conn, _params) do
    body_params = conn.private.open_api_spex.body_params

    config =
      Application.get_env(:lambda_ethereum_consensus, LambdaEthereumConsensus.Validator.Setup, [])

    keystore_dir = Keyword.get(config, :keystore_dir) || @default_keystore_dir
    keystore_pass_dir = Keyword.get(config, :keystore_pass_dir) || @default_keystore_pass_dir

    results =
      Enum.map(body_params.pubkeys, fn pubkey ->
        case Libp2pPort.delete_validator(pubkey |> Utils.hex_decode()) do
          :ok ->
            File.rm!(
              Path.join(
                keystore_dir,
                pubkey <> ".json"
              )
            )

            File.rm!(
              Path.join(
                keystore_pass_dir,
                pubkey <> ".txt"
              )
            )

            %{
              status: "deleted",
              message: "Pubkey: #{inspect(pubkey)}"
            }

          {:error, reason} ->
            Logger.error("[Keystore] Error removing key. Reason: #{reason}")
        end
      end)

    conn
    |> json(%{
      "data" => results
    })
  end
end
