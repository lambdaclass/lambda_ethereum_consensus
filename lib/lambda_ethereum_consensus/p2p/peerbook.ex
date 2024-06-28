defmodule LambdaEthereumConsensus.P2P.Peerbook do
  @moduledoc """
  General peer bookkeeping.
  """
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.Store.KvSchema

  @initial_score 100
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

  @doc """
    Initializes the table in the db by storing an empty peerbook.
  """
  def init() do
    store_peerbook(%{})
  end

  @doc """
  Get some peer from the peerbook.
  """
  def get_some_peer() do
    # TODO: use some algorithm to pick a good peer, for now it's random
    peerbook = fetch_peerbook!()

    if peerbook == %{} do
      nil
    else
      {peer_id, _score} = Enum.random(peerbook)
      peer_id
    end
  end

  def penalize_peer(peer_id) do
    fetch_peerbook!() |> Map.delete(peer_id) |> store_peerbook()
  end

  def handle_new_peer(peer_id) do
    peerbook = fetch_peerbook!()

    if not Map.has_key?(peerbook, peer_id) do
      :telemetry.execute([:peers, :connection], %{id: peer_id}, %{result: "success"})
      Map.put(peerbook, peer_id, @initial_score) |> store_peerbook()
    end

    prune()
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

  defp prune() do
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
  end

  defp store_peerbook(peerbook), do: put("", peerbook)

  defp fetch_peerbook(), do: get("")

  defp fetch_peerbook!() do
    {:ok, peerbook} = fetch_peerbook()
    peerbook
  end
end
