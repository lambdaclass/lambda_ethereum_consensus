defmodule LambdaEthereumConsensus.P2P.IncomingRequests.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {LambdaEthereumConsensus.P2P.IncomingRequests.Receiver, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
