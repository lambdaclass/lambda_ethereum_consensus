defmodule LambdaEthereumConsensus.Beacon.CheckpointSync do
  @moduledoc """
  Functions related to checkpoint-sync.
  """
  require Logger

  use Tesla
  plug(Tesla.Middleware.JSON)

  @doc """
  Retrieves the last finalized state
  """
  @spec get_state(String.t()) :: {:ok, Types.BeaconState.t()} | {:error, any()}
  def get_state(url) do
    with {:error, err} <-
           get_from_url(url, "/eth/v2/debug/beacon/states/finalized", Types.BeaconState) do
      Logger.error("There has been an error retrieving the last finalized state.")
      {:error, err}
    end
  end

  @doc """
  Retrieves the last finalized block
  """
  @spec get_block(String.t()) :: {:ok, Types.SignedBeaconBlock.t()} | {:error, any()}
  def get_block(url) do
    with {:error, err} <-
           get_from_url(url, "/eth/v2/beacon/blocks/finalized", Types.SignedBeaconBlock) do
      Logger.error("There has been an error retrieving the last finalized block.")
      {:error, err}
    end
  end

  defp get_from_url(base_url, path, result_type) do
    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"Accept", "application/octet-stream"}]}
      ])

    full_url =
      base_url
      |> URI.parse()
      |> URI.append_path(path)
      |> URI.to_string()

    with {:ok, response} <- get(client, full_url) do
      Ssz.from_ssz(response.body, result_type)
    end
  end
end
