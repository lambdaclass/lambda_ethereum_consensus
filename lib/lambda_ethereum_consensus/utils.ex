defmodule LambdaEthereumConsensus.Utils do
  @moduledoc """
  Set of utility functions used throughout the project
  """

  use Tesla
  plug(Tesla.Middleware.JSON)

  @doc """
  Syncs the node using an inputed checkpoint
  """
  @spec sync_from_checkpoint(binary) :: any
  def sync_from_checkpoint(url) do
    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"Accept", "application/octet-stream"}]}
      ])

    case get(client, url) do
      {:ok, response} ->
        case Ssz.from_ssz(response.body, SszTypes.BeaconState) do
          {:ok, struct} ->
            struct

          _ ->
            IO.puts("There has been an error syncing from checkpoint.")
            :error
        end

      _ ->
        IO.puts("Invalid checkpoint sync url.")
        :error
    end
  end
end
