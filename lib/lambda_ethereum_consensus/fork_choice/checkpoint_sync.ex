defmodule LambdaEthereumConsensus.ForkChoice.CheckpointSync do
  @moduledoc """
  Functions related to checkpoint-sync.
  """
  require Logger

  use Tesla
  plug(Tesla.Middleware.JSON)

  @doc """
  Syncs the node using an inputed checkpoint
  """
  @spec sync_from_checkpoint(binary) :: {:ok, SszTypes.BeaconState.t()} | {:error, any}
  def sync_from_checkpoint(url) do
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
        case Ssz.from_ssz(response.body, SszTypes.BeaconState) do
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
end
