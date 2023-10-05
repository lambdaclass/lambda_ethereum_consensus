defmodule LambdaEthereumConsensus.P2P.Peerbook do
  @moduledoc """
  General peer bookkeeping.
  """
  use GenServer

  @initial_score 100

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a peer to the peerbook.
  """
  def add_peer(peer_id) do
    GenServer.cast(__MODULE__, {:new_peer, peer_id})
  end

  @doc """
  Get some peer from the peerbook.
  """
  def get_some_peer do
    GenServer.call(__MODULE__, :get_some_peer)
  end

  @impl true
  def init(_opts) do
    peerbook = %{}
    {:ok, peerbook}
  end

  @impl true
  def handle_call(:get_some_peer, _, map) when map == %{}, do: {:reply, nil, %{}}

  @impl true
  def handle_call(:get_some_peer, _, peerbook) do
    # TODO: use some algorithm to pick a good peer, for now it's random
    {peer_id, _score} = Enum.random(peerbook)
    {:reply, peer_id, peerbook}
  end

  @impl true
  def handle_cast({:new_peer, peer_id}, peerbook) do
    updated_peerbook = Map.put(peerbook, peer_id, @initial_score)
    {:noreply, updated_peerbook}
  end
end
