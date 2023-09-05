defmodule LambdaEthereumConsensus.P2P.ReqRespHandler do
  use GenServer

  def start_link([host]) do
    GenServer.start_link(__MODULE__, host)
  end

  @impl true
  def init(host) do
    [
      "status/1",
      "goodbye/1",
      "ping/1",
      "metadata/1",
      "metadata/2"
    ]
    |> Stream.map(&"/eth2/beacon_chain/req/#{&1}/ssz_snappy")
    |> Stream.map(&Libp2p.host_set_stream_handler(host, &1))
    |> Enum.each(fn :ok -> nil end)

    {:ok, host}
  end

  @impl true
  def handle_info({:req, _stream}, state) do
    IO.inspect("got request!")
    {:noreply, state}
  end
end
