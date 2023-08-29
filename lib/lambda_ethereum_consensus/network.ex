defmodule LambdaEthereumConsensus.Network do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  # Callbacks

  @impl true
  def init(_) do
    {:ok, host} = Libp2p.host_new()
    {:ok, host}
  end
end
