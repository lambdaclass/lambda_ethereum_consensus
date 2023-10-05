defmodule LambdaEthereumConsensus.P2P.PeerConsumer do
  @moduledoc """
  This module consumes events created by Discovery.
  """
  alias LambdaEthereumConsensus.P2P.Peerbook
  use Broadway

  def start_link([host]) do
    {:ok, peerstore} = Libp2p.host_peerstore(host)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      context: {host, peerstore},
      producer: [
        module: {LambdaEthereumConsensus.P2P.Discovery, []},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 32]
      ]
    )
  end

  @impl true
  def handle_message(_, %Broadway.Message{data: {id, addrs}} = message, {host, peerstore}) do
    :ok = Libp2p.peerstore_add_addrs(peerstore, id, addrs, Libp2p.ttl_permanent_addr())

    case Libp2p.host_connect(host, id) do
      :ok ->
        Peerbook.add_peer(id)
        message

      {:error, reason} ->
        Broadway.Message.failed(message, reason)
    end
  end
end
