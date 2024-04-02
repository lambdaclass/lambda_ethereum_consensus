defmodule LambdaEthereumConsensus.Beacon.CheckpointSync do
  @moduledoc """
  Functions related to checkpoint-sync.
  """
  require Logger

  use Tesla
  plug(Tesla.Middleware.JSON)

  alias Types.BeaconState
  alias Types.DepositTreeSnapshot
  alias Types.SignedBeaconBlock

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
           get_ssz_from_url(url, "/eth/v2/debug/beacon/states/finalized", BeaconState) do
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
           get_ssz_from_url(url, "/eth/v2/beacon/blocks/#{id}", SignedBeaconBlock) do
      Logger.error("There has been an error retrieving the last finalized block")
      {:error, err}
    end
  end

  @doc """
  Retrieves the latest snapshot of the deposit contract data
  """
  @spec get_deposit_snapshot(String.t()) :: {:ok, DepositTreeSnapshot.t()} | {:error, any()}
  def get_deposit_snapshot(url) do
    case get_json_from_url(url, "/eth/v1/beacon/deposit_snapshot") do
      {:error, err} ->
        Logger.error("There has been an error retrieving the deposit tree snapshot")
        {:error, err}

      {:ok, snapshot} ->
        tree_snapshot = %DepositTreeSnapshot{
          finalized: Map.fetch!(snapshot, "finalized"),
          deposit_root: Map.fetch!(snapshot, "deposit_root"),
          deposit_count: Map.fetch!(snapshot, "deposit_count"),
          execution_block_hash: Map.fetch!(snapshot, "execution_block_hash"),
          execution_block_height: Map.fetch!(snapshot, "execution_block_height")
        }

        {:ok, tree_snapshot}
    end
  end

  defp get_json_from_url(base_url, path) do
    full_url = concat_url(base_url, path)

    with {:ok, response} <- get(full_url) do
      {:ok, response.body |> Map.fetch!("data") |> parse_json()}
    end
  end

  def get_ssz_from_url(base_url, path, result_type) do
    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"Accept", "application/octet-stream"}]}
      ])

    full_url = concat_url(base_url, path)

    with {:ok, response} <- get(client, full_url) do
      Ssz.from_ssz(response.body, result_type)
    end
  end

  defp concat_url(base_url, path) do
    base_url
    |> URI.parse()
    |> URI.append_path(path)
    |> URI.to_string()
  end

  defp parse_json(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, parse_json(v)} end)
  end

  defp parse_json(list) when is_list(list) do
    Enum.map(list, &parse_json/1)
  end

  defp parse_json("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
  defp parse_json(int) when is_binary(int), do: String.to_integer(int, 10)
end
