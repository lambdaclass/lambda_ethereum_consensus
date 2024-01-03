defmodule LambdaEthereumConsensus.P2P.Metadata do
  @moduledoc """
  This module handles Metadata's genserver to fetch and edit.
  """

  use GenServer

  alias LambdaEthereumConsensus.Utils.BitVector
  alias Types.Metadata

  ##########################
  ### Public API
  ##########################

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_seq_number() :: Types.uint64()
  def get_seq_number do
    [seq_number] = get_metadata_attrs([:seq_number])
    seq_number
  end

  @spec get_metadata() :: Metadata.t()
  def get_metadata do
    GenServer.call(__MODULE__, :get_metadata)
  end

  @spec set_attestation_subnet(integer(), boolean()) :: any()
  def set_attestation_subnet(i, set) do
    GenServer.call(__MODULE__, {:set_attestation_subnet, i, set})
  end

  @spec set_sync_committee(integer(), boolean()) :: any()
  def set_sync_committee(i, set) do
    GenServer.call(__MODULE__, {:set_sync_committee, i, set})
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl true
  @spec init(any) :: {:ok, Metadata.t()}
  def init(_opts) do
    {:ok,
     %Metadata{
       seq_number: 0,
       attnets: BitVector.new(0, Constants.attestation_subnet_count()),
       syncnets: BitVector.new(0, Constants.sync_committee_subnet_count())
     }}
  end

  @impl true
  def handle_call({:get_metadata_attrs, attrs}, _from, metadata) do
    values = Enum.map(attrs, &Map.fetch!(metadata, &1))
    {:reply, values, metadata}
  end

  @impl true
  def handle_call(:get_metadata, _from, metadata) do
    {:reply, metadata}
  end

  @impl true
  def handle_cast({:set_attestation_subnet, i, set}, metadata) do
    attnets =
      if set, do: BitVector.set(metadata.attnets, i), else: BitVector.clear(metadata.attnets, i)

    {:noreply,
     %Metadata{
       metadata
       | attnets: attnets,
         seq_number: metadata.seq_number + 1
     }}
  end

  @impl true
  def handle_cast({:set_sync_committee, i, set}, metadata) do
    syncnets =
      if set, do: BitVector.set(metadata.syncnets, i), else: BitVector.clear(metadata.syncnets, i)

    {:noreply,
     %Metadata{
       metadata
       | syncnets: syncnets,
         seq_number: metadata.seq_number + 1
     }}
  end

  ##########################
  ### Private Functions
  ##########################

  @spec get_metadata_attrs([atom()]) :: [any()]
  defp get_metadata_attrs(attrs) do
    GenServer.call(__MODULE__, {:get_metadata_attrs, attrs})
  end
end
