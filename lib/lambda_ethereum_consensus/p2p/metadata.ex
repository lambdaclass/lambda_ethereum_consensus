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
    GenServer.call(__MODULE__, {:get_seq_number})
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
     %{
       seq_number: 0,
       attnets: BitVector.new(0, ChainSpec.get("ATTESTATION_SUBNET_COUNT")),
       syncnets: BitVector.new(0, Constants.sync_committee_subnet_count())
     }}
  end

  @impl true
  def handle_call({:get_seq_number}, _from, metadata) do
    seq_number = Map.fetch!(metadata, :seq_number)
    {:reply, seq_number, metadata}
  end

  @impl true
  def handle_call(:get_metadata, _from, metadata) do
    {:reply,
      %Metadata{
        seq_number: metadata.seq_number
        attnets: metadata.attnets
        syncnets: metadata.syncnets
      }
    }
  end

  @impl true
  def handle_cast({:set_attestation_subnet, i, set}, metadata) do
    attnets = set_or_clear(metadata.attnets, i, set)

    {:noreply,
     %{
       metadata
       | attnets: attnets,
         seq_number: metadata.seq_number + 1
     }}
  end

  @impl true
  def handle_cast({:set_sync_committee, i, set}, metadata) do
    syncnets = set_or_clear(metadata.syncnets, i, set)

    {:noreply,
     %{
       metadata
       | syncnets: syncnets,
         seq_number: metadata.seq_number + 1
     }}
  end

  ##########################
  ### Private Functions
  ##########################

  @spec set_or_clear(BitVector.t(), integer(), boolean()) :: BitVector.t()
  defp set_or_clear(bitvector, i, set) do
    if set do
      BitVector.set(bitvector, i)
    else
      BitVector.clear(bitvector, i)
    end
  end
end
