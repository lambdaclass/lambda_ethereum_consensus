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
    init_args = [use_discv5: true, discovery_addr: "0.0.0.0:25100", bootnodes: @bootnodes]
    start_link_supervised!({Libp2pPort, init_args})
    # We should never receive messages
    # TODO: we should implement notifications for every discovered peer
    receive do
      _ -> nil
    end
  end
end
