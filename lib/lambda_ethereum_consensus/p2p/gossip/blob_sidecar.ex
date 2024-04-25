defmodule LambdaEthereumConsensus.P2P.Gossip.BlobSideCar do
  @moduledoc """
  This module handles blob sidecar gossipsub topics.
  """
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.Store.BlobDb

  use GenServer

  require Logger

  @type topics :: [String.t()]

  ##########################
  ### Public API
  ##########################

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start() do
    GenServer.call(__MODULE__, :start)
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl true
  @spec init(any()) :: {:ok, topics()} | {:stop, any()}
  def init(_init_arg) do
    # TODO: this doesn't take into account fork digest changes
    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)

    topics =
      Enum.map(0..(ChainSpec.get("BLOB_SIDECAR_SUBNET_COUNT") - 1), fn i ->
        "/eth2/#{fork_context}/blob_sidecar_#{i}/ssz_snappy"
      end)

    Enum.map(topics, &Libp2pPort.join_topic/1)
    {:ok, topics}
  end

  @impl true
  def handle_call(:start, _from, topics) do
    Enum.map(topics, &Libp2pPort.subscribe_to_topic/1)
    {:reply, :ok, topics}
  end

  @impl true
  def handle_info({:gossipsub, {_topic, msg_id, message}}, topics) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.BlobSidecar{index: blob_index} = blob} <-
           Ssz.from_ssz(uncompressed, Types.BlobSidecar) |> IO.inspect() do
      Logger.debug("[Gossip] Blob sidecar received, with index #{blob_index}")
      BlobDb.store_blob(blob)
      Libp2pPort.validate_message(msg_id, :accept)
    else
      {:error, reason} ->
        Logger.warning("[Gossip] Blob rejected, reason: #{inspect(reason)}")
        Libp2pPort.validate_message(msg_id, :reject)
    end

    {:noreply, topics}
  end
end
