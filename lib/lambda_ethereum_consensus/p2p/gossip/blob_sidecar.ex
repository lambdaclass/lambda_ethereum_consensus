defmodule LambdaEthereumConsensus.P2P.Gossip.BlobSideCar do
  @moduledoc """
  This module handles blob sidecar gossipsub topics.
  """
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias LambdaEthereumConsensus.Store.BlobDb

  require Logger

  @behaviour Handler

  @impl true
  def handle_gossip_message(_topic, msg_id, message) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.BlobSidecar{index: blob_index} = blob} <-
           Ssz.from_ssz(uncompressed, Types.BlobSidecar) do
      Logger.debug("[Gossip] Blob sidecar received, with index #{blob_index}")
      BlobDb.store_blob(blob)
      Libp2pPort.validate_message(msg_id, :accept)
    else
      {:error, reason} ->
        Logger.warning("[Gossip] Blob rejected, reason: #{inspect(reason)}")
        Libp2pPort.validate_message(msg_id, :reject)
    end
  end

  @spec join_topics() :: :ok
  def join_topics() do
    topics()
    |> Enum.each(fn topic_name -> Libp2pPort.join_topic(self(), topic_name) end)
  end

  @spec subscribe_to_topics() :: :ok | {:error, String.t()}
  def subscribe_to_topics() do
    topics()
    |> Enum.each(fn topic ->
      Libp2pPort.subscribe_to_topic(topic, __MODULE__)
      |> case do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("[Gossip] Subscription failed: '#{reason}'")
          {:error, reason}
      end
    end)
  end

  defp topics() do
    # TODO: this doesn't take into account fork digest changes
    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)

    # Generate blob sidecar topics
    # NOTE: there's one per blob index in Deneb (6 blobs per block)
    Enum.map(0..(ChainSpec.get("BLOB_SIDECAR_SUBNET_COUNT") - 1), fn i ->
      "/eth2/#{fork_context}/blob_sidecar_#{i}/ssz_snappy"
    end)
  end
end
