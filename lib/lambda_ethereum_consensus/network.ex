defmodule LambdaEthereumConsensus.Network do
  use Broadway

  def start_link(_opts) do
    {:ok, host} = Libp2p.host_new()
    {:ok, peerstore} = Libp2p.host_peerstore(host)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      context: {host, peerstore},
      producer: [
        module: {LambdaEthereumConsensus.Discovery, []},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 10]
      ]
    )
  end

  @impl true
  def handle_message(_, %Broadway.Message{data: {id, addrs}} = message, {host, peerstore}) do
    :ok = Libp2p.peerstore_add_addrs(peerstore, id, addrs, Libp2p.ttl_permanent_addr())
    Libp2p.host_connect(host, id)

    message
  end
end
