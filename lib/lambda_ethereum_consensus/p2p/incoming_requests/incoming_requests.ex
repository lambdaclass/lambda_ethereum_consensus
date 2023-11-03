defmodule LambdaEthereumConsensus.P2P.IncomingRequests do
  @moduledoc """
  This module is a ``Supervisor`` over ``Receiver`` and ``Handler``.
  """
  use Supervisor

  alias __MODULE__

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Task.Supervisor, name: IncomingRequests.Handler},
      {IncomingRequests.Receiver, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
