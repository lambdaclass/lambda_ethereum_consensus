defmodule LambdaEthereumConsensus.Beacon.CheckpointSync do
  @moduledoc """
  Functions related to checkpoint-sync.
  """
  require Logger

  use Tesla
  plug(Tesla.Middleware.JSON)

  alias Types.BeaconState
  alias Types.SignedBeaconBlock

  use HardForkAliasInjection

  @doc """
  Safely retrieves the last finalized state and block
  """
  @spec get_finalized_block_and_state(String.t(), Types.root()) ::
          {:ok, {BeaconState.t(), SignedBeaconBlock.t()}} | {:error, any()}
  def get_finalized_block_and_state(url, genesis_validators_root) do
    tasks = [Task.async(__MODULE__, :get_state, [url]), Task.async(__MODULE__, :get_block, [url])]

    case Task.await_many(tasks, 60_000) do
      [{:ok, state}, {:ok, block}] ->
        if state.genesis_validators_root == genesis_validators_root do
          check_match(url, state, block)
        else
          Logger.error("The fetched state's genesis validators root differs from the network's")
          {:error, "wrong genesis validators root"}
        end

      res ->
        Enum.find(res, fn {:error, _} -> true end)
    end
  end

  defp check_match(_, state, block) when state.slot == block.message.slot,
    do: {:ok, {state, block}}

  defp check_match(url, state, _block) do
    with {:ok, new_block} <- get_block(url, state.slot) do
      {:ok, {state, new_block}}
    end
  end

  @doc """
  Retrieves the last finalized state
  """
  @spec get_state(String.t()) :: {:ok, BeaconState.t()} | {:error, any()}
  def get_state(url) do
    with {:error, err} <-
           get_from_url(url, "/eth/v2/debug/beacon/states/finalized", BeaconState) do
      Logger.error("There has been an error retrieving the last finalized state")
      {:error, err}
    end
  end

  @doc """
  Retrieves the last finalized block
  """
  @spec get_block(String.t()) :: {:ok, SignedBeaconBlock.t()} | {:error, any()}
  def get_block(url, id \\ "finalized") do
    with {:error, err} <-
           get_from_url(url, "/eth/v2/beacon/blocks/#{id}", SignedBeaconBlock) do
      Logger.error("There has been an error retrieving the last finalized block")
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
