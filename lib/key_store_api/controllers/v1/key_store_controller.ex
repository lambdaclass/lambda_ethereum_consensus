defmodule KeyStoreApi.V1.KeyStoreController do
  use KeyStoreApi, :controller

  alias BeaconApi.Utils
  alias KeyStoreApi.ApiSpec
  alias LambdaEthereumConsensus.Libp2pPort

  require Logger

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @keystore_dir Keystore.get_keystore_dir()
  @keystore_pass_dir Keystore.get_keystore_pass_dir()

  # NOTE: this function is required by OpenApiSpex, and should return the information
  #  of each specific endpoint. We just return the specific entry from the parsed spec.
  def open_api_operation(:get_keys),
    do: ApiSpec.spec().paths["/eth/v1/keystores"].get

  def open_api_operation(:add_keys),
    do: ApiSpec.spec().paths["/eth/v1/keystores"].post

  def open_api_operation(:delete_keys),
    do: ApiSpec.spec().paths["/eth/v1/keystores"].delete

  @doc """
  Returns all the keystores associated with the node.
  """
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

  @doc """
  For each keystore received:
  - Creates a keystore_file and keystore_pass_file in their respective directories.
  - Creates a new validator in Libp2pPort.
  """
  @spec add_keys(Plug.Conn.t(), any) :: Plug.Conn.t()
  def add_keys(conn, _params) do
    body_params = conn.private.open_api_spex.body_params

    results =
      Enum.zip(body_params.keystores, body_params.passwords)
      |> Enum.map(fn {keystore_str, password_str} ->
        # TODO (#1268): handle bad requests
        keystore = Keystore.decode_str!(keystore_str, password_str)

        base_name = keystore.pubkey |> Utils.hex_encode()

        File.write!(get_keystore_file_path(base_name), keystore_str)
        File.write!(get_keystore_pass_file_path(base_name), password_str)

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

  @doc """
  For each pubkey received:
  - Removes the associated validator from Libp2pPort.
  - Removes the keystore_file and keystore_pass_file associated with the key.
  """
  @spec delete_keys(Plug.Conn.t(), any) :: Plug.Conn.t()
  def delete_keys(conn, _params) do
    body_params = conn.private.open_api_spex.body_params

    results =
      Enum.map(body_params.pubkeys, fn pubkey ->
        case Libp2pPort.delete_validator(pubkey |> Utils.hex_decode()) do
          :ok ->
            File.rm!(get_keystore_file_path(pubkey))
            File.rm!(get_keystore_pass_file_path(pubkey))

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

  defp get_keystore_file_path(base_name), do: Path.join(@keystore_dir, base_name <> ".json")

  defp get_keystore_pass_file_path(base_name),
    do: Path.join(@keystore_pass_dir, base_name <> ".txt")
end
