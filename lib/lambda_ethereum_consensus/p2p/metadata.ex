defmodule LambdaEthereumConsensus.P2P.Metadata do
  @moduledoc """
  This module handles node's Metadata (fetch and edit).
  """

  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Utils.BitVector
  alias Types.Metadata

  @metadata_prefix "metadata"

  ##########################
  ### Public API
  ##########################

  @doc """
  Initializes the table in the db by creating and storing empty metadata.
  """
  def init() do
    Metadata.empty() |> store_metadata()
  end

  @spec get_seq_number() :: Types.uint64()
  def get_seq_number() do
    %Metadata{seq_number: seq_number} = fetch_metadata!()
    seq_number
  end

  @spec get_metadata() :: Metadata.t()
  def get_metadata() do
    fetch_metadata!()
  end

  @spec set_attnet(non_neg_integer()) :: :ok
  def set_attnet(i) do
    update_metadata(fn metadata -> Map.update!(metadata, :attnets, &BitVector.set(&1, i)) end)
  end

  @spec clear_attnet(non_neg_integer()) :: :ok
  def clear_attnet(i) do
    update_metadata(fn metadata -> Map.update!(metadata, :attnets, &BitVector.clear(&1, i)) end)
  end

  @spec set_syncnet(non_neg_integer()) :: :ok
  def set_syncnet(i) do
    update_metadata(fn metadata -> Map.update!(metadata, :syncnets, &BitVector.set(&1, i)) end)
  end

  @spec clear_syncnet(non_neg_integer()) :: :ok
  def clear_syncnet(i) do
    update_metadata(fn metadata -> Map.update!(metadata, :syncnets, &BitVector.clear(&1, i)) end)
  end

  ##########################
  ### Private Functions
  ##########################

  defp update_metadata(f) when is_function(f) do
    fetch_metadata!() |> f.() |> increment_seqnum() |> store_metadata()
  end

  defp increment_seqnum(state), do: %{state | seq_number: state.seq_number + 1}

  defp store_metadata(%Metadata{} = map) do
    :telemetry.span([:db, :latency], %{}, fn ->
      {Db.put(
         @metadata_prefix,
         :erlang.term_to_binary(map)
       ), %{module: "metadata", action: "persist"}}
    end)
  end

  defp fetch_metadata() do
    with {:ok, binary} <-
           :telemetry.span([:db, :latency], %{}, fn ->
             {Db.get(@metadata_prefix), %{module: "metadata", action: "fetch"}}
           end) do
      {:ok, :erlang.binary_to_term(binary)}
    end
  end

  defp fetch_metadata!() do
    {:ok, metadata} = fetch_metadata()
    metadata
  end
end
