defmodule LambdaEthereumConsensus.P2P.Peerbook do
  @moduledoc """
  General peer bookkeeping.
  """
  use GenServer
  alias LambdaEthereumConsensus.Libp2pPort

  @initial_score 100
  @peer_penalty -10
  @peer_reward 10

  ##########################
  ### Public API
  ##########################

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get some peer from the peerbook.
  """
  def get_some_peer do
    GenServer.call(__MODULE__, :get_some_peer)
  end

  @doc """
  Penalize peer.
  """
  def penalize_peer(peer_id), do: score_peer(peer_id, @peer_penalty)

  @doc """
  Reward peer.
  """
  def reward_peer(peer_id), do: score_peer(peer_id, @peer_reward)

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl true
  def init(_opts) do
    Libp2pPort.set_new_peer_handler(self())
    peerbook = %{}
    {:ok, peerbook}
  end

  @impl true
  def handle_call(:get_some_peer, _, map) when map == %{}, do: {:reply, nil, %{}}

  @impl true
  def handle_call(:get_some_peer, _, peerbook) do
    {peer_id, _score} = Enum.max_by(peerbook, fn {_, score} -> score end)
    # We reduce the peer's score so that we don't keep requesting from the same peer
    updated_peerbook = Map.update!(peerbook, peer_id, &(&1 - @peer_reward))
    {:reply, peer_id, updated_peerbook}
  end

  @impl true
  def handle_cast({:rate_peer, peer_id, score}, peerbook) do
    new_score =
      peerbook
      |> Map.fetch!(peer_id)
      |> update_score(score)

    # We delete peers that don't respond to requests
    updated_peerbook =
      if new_score > 0 do
        Map.delete(peerbook, peer_id)
      else
        Map.put(peerbook, peer_id, new_score)
      end

    {:noreply, updated_peerbook}
  end

  @impl true
  def handle_info({:new_peer, peer_id}, peerbook) do
    updated_peerbook = Map.put(peerbook, peer_id, @initial_score)
    {:noreply, updated_peerbook}
  end

  ##########################
  ### Private Functions
  ##########################

  defp score_peer(peer_id, score) do
    GenServer.cast(__MODULE__, {:rate_peer, peer_id, score})
  end

  defp update_score(old_score, diff) do
    (old_score + diff)
    |> min(@initial_score)
    |> max(0)
  end
end
