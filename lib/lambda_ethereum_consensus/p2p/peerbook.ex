defmodule LambdaEthereumConsensus.P2P.Peerbook do
  @moduledoc """
  General peer bookkeeping.
  """
  use GenServer
  alias LambdaEthereumConsensus.Libp2pPort

  @initial_score 100
  @prune_interval 1000
  @prune_percentage 0.15

  @metadata_protocol_id "/eth2/beacon_chain/req/metadata/2/ssz_snappy"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get some peer from the peerbook.
  """
  def get_some_peer do
    GenServer.call(__MODULE__, :get_some_peer)
  end

  @impl true
  def init(_opts) do
    Libp2pPort.set_new_peer_handler(self())
    peerbook = %{}
    Process.send_after(self(), :prune, @prune_interval)
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
  def handle_cast({:remove_peer, peer_id}, peerbook) do
    :telemetry.execute([:peers, :prune], %{})
    updated_peerbook = Map.delete(peerbook, peer_id)
    {:noreply, updated_peerbook}
  end

  @impl true
  def handle_info({:new_peer, peer_id}, peerbook) do
    :telemetry.execute([:peers, :connection], %{id: peer_id}, %{result: "success"})
    updated_peerbook = Map.put(peerbook, peer_id, @initial_score)
    {:noreply, updated_peerbook}
  end

  @impl true
  def handle_info(:prune, peerbook) do
    prune_size = (map_size(peerbook) * @prune_percentage) |> round()

    peerbook
    |> Map.keys()
    |> Enum.take_random(prune_size)
    |> Enum.each(fn peer_id -> Task.start(__MODULE__, :challenge_peer, [peer_id]) end)

    Process.send_after(self(), :prune, @prune_interval)
    {:noreply, peerbook}
  end

  def challenge_peer(peer_id) do
    case Libp2pPort.send_request(peer_id, @metadata_protocol_id, "") do
      {:ok, <<0, 17>> <> _payload} -> nil
      _ -> GenServer.cast(__MODULE__, {:remove_peer, peer_id})
    end
  end
end
