defmodule LambdaEthereumConsensus.P2P.Gossip.BlobSideCar do
  @moduledoc """
  This module handles blob sidecar gossipsub topics.
  """
  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip.Handler

  require Logger

  @behaviour Handler

  @impl Handler
  def handle_gossip_message(store, _topic, msg_id, message) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.BlobSidecar{index: blob_index} = blob} <-
           Ssz.from_ssz(uncompressed, Types.BlobSidecar) do
      Logger.debug("[Gossip] Blob sidecar received, with index #{blob_index}")
      Libp2pPort.validate_message(msg_id, :accept)
      # TODO: (#1406) Enhance the API to reduce unnecessary wrappers (:ok + list)
      PendingBlocks.process_blobs(store, {:ok, [blob]}) |> then(&elem(&1, 1))
    else
      {:error, reason} ->
        Logger.warning("[Gossip] Blob rejected, reason: #{inspect(reason)}")
        Libp2pPort.validate_message(msg_id, :reject)
        store
    end
  end

  @spec subscribe_to_topics() :: :ok | {:error, String.t()}
  def subscribe_to_topics() do
    Enum.each(topics(), fn topic ->
      case Libp2pPort.subscribe_to_topic(topic, __MODULE__) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("[Gossip] Subscription failed: '#{reason}'")
          {:error, reason}
      end
    end)
  end

  def topics() do
    # TODO: this doesn't take into account fork digest changes
    fork_context = ForkChoice.get_fork_digest() |> Base.encode16(case: :lower)

    # Generate blob sidecar topics
    # NOTE: there's one per blob index in Deneb (6 blobs per block)
    Enum.map(0..(ChainSpec.get("BLOB_SIDECAR_SUBNET_COUNT") - 1), fn i ->
      "/eth2/#{fork_context}/blob_sidecar_#{i}/ssz_snappy"
    end)
  end
end
