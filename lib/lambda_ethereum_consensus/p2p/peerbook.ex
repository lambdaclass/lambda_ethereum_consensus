defmodule LambdaEthereumConsensus.P2P.Peerbook do
  @moduledoc """
  General peer bookkeeping.
  """
  use GenServer
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.Store.KvSchema

  @initial_score 100
  @prune_interval 2000
  @target_peers 128
  @max_prune_size 8
  @prune_percentage 0.05

  @metadata_protocol_id "/eth2/beacon_chain/req/metadata/2/ssz_snappy"

  use KvSchema, prefix: "peerbook"

  @impl KvSchema
  @spec encode_key(String.t()) :: {:ok, binary()} | {:error, binary()}
  def encode_key(key), do: {:ok, key}

  @impl KvSchema
  @spec decode_key(binary()) :: {:ok, String.t()} | {:error, binary()}
  def decode_key(key), do: {:ok, key}

  @impl KvSchema
  @spec encode_value(map()) :: {:ok, binary()} | {:error, binary()}
  def encode_value(peerbook), do: {:ok, :erlang.term_to_binary(peerbook)}

  @impl KvSchema
  @spec decode_value(binary()) :: {:ok, map()} | {:error, binary()}
  def decode_value(bin), do: {:ok, :erlang.binary_to_term(bin)}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get some peer from the peerbook.
  """
  def get_some_peer() do
    GenServer.call(__MODULE__, :get_some_peer)
  end

  def penalize_peer(peer_id) do
    GenServer.cast(__MODULE__, {:remove_peer, peer_id})
  end

  def handle_new_peer(peer_id) do
    GenServer.cast(__MODULE__, {:new_peer, peer_id})
  end

  @doc """
    Initializes the table in the db by storing an empty peerbook.
  """
  @impl true
  def init(_opts) do
    store_peerbook(%{})
    schedule_pruning()
    {:ok, nil}
  end

  @impl true
  def handle_call(:get_some_peer, _, map) when map == %{}, do: {:reply, nil, %{}}

  @impl true
  def handle_call(:get_some_peer, _, _peerbook) do
    # TODO: use some algorithm to pick a good peer, for now it's random
    peerbook = fetch_peerbook!()

    if peerbook == %{} do
      {:reply, nil, nil}
    else
      {peer_id, _score} = Enum.random(peerbook)
      {:reply, peer_id, nil}
    end
  end

  @impl true
  def handle_cast({:remove_peer, peer_id}, _peerbook) do
    fetch_peerbook!() |> Map.delete(peer_id) |> store_peerbook()
    {:noreply, nil}
  end

  @impl true
  def handle_cast({:new_peer, peer_id}, _peerbook) do
    peerbook = fetch_peerbook!()

    if Map.has_key?(peerbook, peer_id) do
      {:noreply, nil}
    else
      :telemetry.execute([:peers, :connection], %{id: peer_id}, %{result: "success"})
      Map.put(peerbook, peer_id, @initial_score) |> store_peerbook()
      {:noreply, nil}
    end
  end

  @impl true
  def handle_info(:prune, _peerbook) do
    peerbook = fetch_peerbook!()
    len = map_size(peerbook)

    if len != 0 do
      prune_size =
        (len * @prune_percentage)
        |> round()
        |> min(@max_prune_size)
        |> min(len - @target_peers)
        |> max(0)

      n = :rand.uniform(len)

      peerbook
      |> Map.keys()
      |> Stream.drop(n)
      |> Stream.take(prune_size)
      |> Enum.each(fn peer_id -> Task.start(__MODULE__, :challenge_peer, [peer_id]) end)
    end

    schedule_pruning()
    {:noreply, nil}
  end

  def challenge_peer(peer_id) do
    case Libp2pPort.send_request(peer_id, @metadata_protocol_id, "") do
      {:ok, <<0, 17>> <> _payload} ->
        :telemetry.execute([:peers, :challenge], %{}, %{result: "passed"})

      _ ->
        :telemetry.execute([:peers, :challenge], %{}, %{result: "failed"})
        penalize_peer(peer_id)
    end
  end

  def schedule_pruning(interval \\ @prune_interval) do
    Process.send_after(__MODULE__, :prune, interval)
  end

  defp store_peerbook(peerbook), do: put("", peerbook)

  defp fetch_peerbook(), do: get("")

  defp fetch_peerbook!() do
    {:ok, peerbook} = fetch_peerbook()
    peerbook
  end
end
