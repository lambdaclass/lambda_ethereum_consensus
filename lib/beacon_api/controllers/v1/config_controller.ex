defmodule BeaconApi.V1.ConfigController do
  use BeaconApi, :controller
  require Logger

  alias BeaconApi.ApiSpec
  alias BeaconApi.Utils

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @chain_spec_removed_keys [
    "ATTESTATION_SUBNET_COUNT",
    "KZG_COMMITMENT_INCLUSION_PROOF_DEPTH",
    "UPDATE_TIMEOUT"
  ]
  @chain_spec_renamed_keys [
    {"MAXIMUM_GOSSIP_CLOCK_DISPARITY", "MAXIMUM_GOSSIP_CLOCK_DISPARITY_MILLIS"}
  ]
  @chain_spec_hex_fields [
    "TERMINAL_BLOCK_HASH",
    "DEPOSIT_CONTRACT_ADDRESS",
    "MESSAGE_DOMAIN_INVALID_SNAPPY",
    "MESSAGE_DOMAIN_VALID_SNAPPY"
  ]

  # NOTE: this function is required by OpenApiSpex, and should return the information
  #  of each specific endpoint. We just return the specific entry from the parsed spec.
  def open_api_operation(:get_spec),
    do: ApiSpec.spec().paths["/eth/v1/config/spec"].get

  # TODO: This is still an incomplete implementation, it should return some constants
  # along with the chain spec. It's enough for assertoor.
  @spec get_spec(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_spec(conn, _params), do: json(conn, %{"data" => chain_spec()})

  defp chain_spec() do
    ChainSpec.get_all()
    |> Map.drop(@chain_spec_removed_keys)
    |> rename_keys(@chain_spec_renamed_keys)
    |> Map.new(fn
      {k, v} when is_integer(v) -> {k, Integer.to_string(v)}
      {k, v} when k in @chain_spec_hex_fields -> {k, Utils.hex_encode(v)}
      {k, v} when is_binary(v) -> if String.ends_with?(k, "_FORK_VERSION"), do: {k, Utils.hex_encode(v)}, else: {k, v}
      {k, v} -> {k, v}
    end)
  end

  defp rename_keys(config, renamed_keys) do
    renamed_keys
    |> Enum.reduce(config, fn {old_key, new_key}, config ->
      case Map.get(config, old_key) do
        nil -> config
        value -> Map.put_new(config, new_key, value) |> Map.delete(old_key)
      end
    end)
  end
end
