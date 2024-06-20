defmodule LambdaEthereumConsensus.P2P.Metadata do
  @moduledoc """
  This module handles Metadata's genserver to fetch and edit.
  """

  use GenServer

  alias LambdaEthereumConsensus.Utils.BitVector
  alias LambdaEthereumConsensus.Types.Base.Metadata

  ##########################
  ### Public API
  ##########################

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_seq_number() :: Types.uint64()
  def get_seq_number() do
    GenServer.call(__MODULE__, :get_seq_number)
  end

  @spec get_metadata() :: Metadata.t()
  def get_metadata() do
    GenServer.call(__MODULE__, :get_metadata)
  end

  @spec set_attnet(non_neg_integer()) :: :ok
  def set_attnet(i), do: GenServer.cast(__MODULE__, {:set_attestation_subnet, i, true})
  @spec clear_attnet(non_neg_integer()) :: :ok
  def clear_attnet(i), do: GenServer.cast(__MODULE__, {:set_attestation_subnet, i, false})

  @spec set_syncnet(non_neg_integer()) :: :ok
  def set_syncnet(i), do: GenServer.cast(__MODULE__, {:set_sync_committee, i, true})
  @spec clear_syncnet(non_neg_integer()) :: :ok
  def clear_syncnet(i), do: GenServer.cast(__MODULE__, {:set_sync_committee, i, false})

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl true
  def init(_opts) do
    Metadata.empty() |> Metadata.store_metadata()
    {:ok, nil}
  end

  @impl true
  def handle_call(:get_seq_number, _, _state) do
    %Metadata{seq_number: seq_number} = Metadata.fetch_metadata!()
    {:reply, seq_number, nil}
  end

  @impl true
  def handle_call(:get_metadata, _, _metadata), do: {:reply, Metadata.fetch_metadata!(), nil}

  @impl true
  def handle_cast({:set_attestation_subnet, i, set}, _metadata) do
    metadata = Metadata.fetch_metadata!()
    attnets = set_or_clear(metadata.attnets, i, set)
    %{metadata | attnets: attnets} |> increment_seqnum() |> Metadata.store_metadata()
    {:noreply, nil}
  end

  @impl true
  def handle_cast({:set_sync_committee, i, set}, _metadata) do
    metadata = Metadata.fetch_metadata!()
    syncnets = set_or_clear(metadata.syncnets, i, set)
    %{metadata | syncnets: syncnets} |> increment_seqnum() |> Metadata.store_metadata()
    {:noreply, nil}
  end

  ##########################
  ### Private Functions
  ##########################

  @spec set_or_clear(BitVector.t(), non_neg_integer(), boolean()) :: BitVector.t()
  defp set_or_clear(bitvector, i, true), do: BitVector.set(bitvector, i)
  defp set_or_clear(bitvector, i, false), do: BitVector.clear(bitvector, i)

  defp increment_seqnum(state), do: %{state | seq_number: state.seq_number + 1}
end
