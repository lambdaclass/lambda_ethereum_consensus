defmodule LambdaEthereumConsensus.P2P.Peerbook do
  @moduledoc """
  General peer bookkeeping.
  """
  use GenServer

  @initial_score 100

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    peerbook = %{}
    pb_size = 0
    {:ok, {peerbook, pb_size}}
  end

  @impl true
  def handle_call(:get_some_peer, _, {%{}, 0}), do: {:reply, nil, {%{}, 0}}

  @impl true
  def handle_call(:get_some_peer, _, {peerbook, pb_size}) do
    # TODO: use some algorithm to pick a good peer, for now it's random
    n = :rand.uniform(pb_size) - 1
    {peer_id, _score} = peerbook |> Enum.at(n)
    {:reply, peer_id, {peerbook, pb_size}}
  end

  @impl true
  def handle_cast({:new_peer, peer_id}, {peerbook, pb_size}) do
    updated_peerbook = Map.put(peerbook, peer_id, @initial_score)
    {:noreply, {updated_peerbook, pb_size + 1}}
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
end
