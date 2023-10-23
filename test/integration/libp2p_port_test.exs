defmodule Integration.Libp2pPortTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.Libp2pPort

  @bootnodes Application.compile_env(
               :lambda_ethereum_consensus,
               LambdaEthereumConsensus.P2P.Discovery
             )[:bootnodes]

  @tag :skip
  @tag timeout: :infinity
  test "discover peers indefinitely" do
    init_args = [
      enable_discovery: true,
      discovery_addr: "0.0.0.0:25100",
      bootnodes: @bootnodes,
      new_peer_handler: self()
    ]

    start_link_supervised!({Libp2pPort, init_args})

    Stream.iterate(0, fn _ ->
      receive do
        {:new_peer, peer_id} -> peer_id |> Base.encode16() |> IO.puts()
      end
    end)
    |> Stream.run()
  end
end
