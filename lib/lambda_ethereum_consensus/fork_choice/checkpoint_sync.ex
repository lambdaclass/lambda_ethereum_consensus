defmodule LambdaEthereumConsensus.ForkChoice.CheckpointSync do
  @moduledoc """
  Functions related to checkpoint-sync.
  """
  require Logger

  use Tesla
  plug(Tesla.Middleware.JSON)

  @doc """
  Retrieves the last finalized state
  """
  @spec get_last_finalized_state(binary) :: {:ok, Types.BeaconState.t()} | {:error, any}
  def get_last_finalized_state(url) do
    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"Accept", "application/octet-stream"}]}
      ])

    full_url =
      url
      |> URI.parse()
      |> URI.append_path("/eth/v2/debug/beacon/states/finalized")
      |> URI.to_string()

    case get(client, full_url) do
      {:ok, response} ->
        case Ssz.from_ssz(response.body, Types.BeaconState) do
          {:ok, struct} ->
            {:ok, struct}

          {:error, error} ->
            Logger.error("There has been an error syncing from checkpoint.")
            {:error, error}
        end

      error ->
        Logger.error("Invalid checkpoint sync url.")
        {:error, error}
    end
  end

  @doc """
  Retrieves the last finalized block
  """
  @spec get_last_finalized_block(binary) :: {:ok, Types.SignedBeaconBlock.t()} | {:error, any}
  def get_last_finalized_block(url) do
    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"Accept", "application/octet-stream"}]}
      ])

    full_url =
      url
      |> URI.parse()
      |> URI.append_path("/eth/v2/beacon/blocks/finalized")
      |> URI.to_string()

    case get(client, full_url) do
      {:ok, response} ->
        case Ssz.from_ssz(response.body, Types.SignedBeaconBlock) do
          {:ok, struct} ->
            {:ok, struct}

          {:error, error} ->
            Logger.error("There has been an error retrieving the last finalized block.")
            {:error, error}
        end

      error ->
        Logger.error("Invalid checkpoint sync url.")
        {:error, error}
    end
  end
end
