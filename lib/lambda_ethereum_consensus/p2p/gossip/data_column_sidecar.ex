defmodule LambdaEthereumConsensus.P2P.Gossip.DataColumnSidecar do
  @moduledoc """
  Handles `data_column_sidecar_{subnet_id}` gossipsub topics (Fulu / EIP-7594).

  Nodes subscribe only to their **custody subnets** (4-8 out of 128), keeping
  bandwidth comparable to the Electra blob subnet approach.
  """

  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias LambdaEthereumConsensus.StateTransition.DasCore

  require Logger

  @behaviour Handler

  @impl Handler
  def handle_gossip_message(store, _topic, msg_id, message) do
    with {:ok, uncompressed} <- :snappyer.decompress(message),
         {:ok, %Types.DataColumnSidecar{index: column_index} = sidecar} <-
           Ssz.from_ssz(uncompressed, Types.DataColumnSidecar) do
      Logger.debug("[Gossip] Data column sidecar received, column #{column_index}")
      Libp2pPort.validate_message(msg_id, :accept)
      PendingBlocks.process_data_columns(store, {:ok, [sidecar]}) |> then(&elem(&1, 1))
    else
      {:error, reason} ->
        Logger.warning("[Gossip] Data column sidecar rejected, reason: #{inspect(reason)}")
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
          Logger.error("[Gossip] Data column subscription failed: '#{reason}'")
          {:error, reason}
      end
    end)
  end

  @doc """
  Returns the gossip topics for this node's custody subnets.

  The node subscribes only to the subnets corresponding to its custody columns,
  not all `DATA_COLUMN_SIDECAR_SUBNET_COUNT` subnets.
  """
  def topics() do
    # TODO: this doesn't take into account fork digest changes
    fork_context = ForkChoice.get_fork_digest() |> Base.encode16(case: :lower)

    custody_column_indices()
    |> Enum.map(&column_index_to_subnet_id/1)
    |> Enum.uniq()
    |> Enum.map(fn subnet_id ->
      "/eth2/#{fork_context}/data_column_sidecar_#{subnet_id}/ssz_snappy"
    end)
  end

  # Maps a column index to its gossip subnet.
  # Subnets cover equal slices of the column space:
  #   subnet_id = floor(column_index * DATA_COLUMN_SIDECAR_SUBNET_COUNT / NUMBER_OF_COLUMNS)
  defp column_index_to_subnet_id(column_index) do
    subnet_count = ChainSpec.get("DATA_COLUMN_SIDECAR_SUBNET_COUNT")
    n_columns = ChainSpec.get("NUMBER_OF_COLUMNS")
    div(column_index * subnet_count, n_columns)
  end

  # Returns the column indices this node is responsible for.
  # node_id comes from the libp2p ENR; defaults to 0 until Phase 5 wires it up.
  defp custody_column_indices() do
    node_id = Application.get_env(:lambda_ethereum_consensus, :node_id, 0)
    custody_group_count = ChainSpec.get("CUSTODY_REQUIREMENT")
    DasCore.get_custody_columns(node_id, custody_group_count)
  end
end
