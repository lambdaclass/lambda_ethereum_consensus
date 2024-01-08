defmodule LambdaEthereumConsensus.P2P.IncomingRequests.Receiver do
  @moduledoc """
  This module receives Req/Resp domain requests, and dispatches them to
  ``LambdaEthereumConsensus.P2P.IncomingRequests.Handler.handle_req/3``.
  """
  use GenServer
  require Logger

  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.IncomingRequests.Handler

  @prefix "/eth2/beacon_chain/req/"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(_opts) do
    [
      "status/1",
      "goodbye/1",
      "ping/1",
      "beacon_blocks_by_range/2",
      "beacon_blocks_by_root/2",
      "metadata/2"
    ]
    |> Stream.map(&Enum.join([@prefix, &1, "/ssz_snappy"]))
    |> Stream.map(&Libp2pPort.set_handler/1)
    |> Enum.each(fn :ok -> nil end)

    {:ok, nil}
  end

  @impl true
  def handle_info({:request, {@prefix <> name, message_id, message}}, state) do
    Logger.debug("'#{name}' request received")

    args = [name, message_id, message]
    Task.Supervisor.async_nolink(Handler, Handler, :handle, args)

    {:noreply, state}
  end

  # The task completed successfully
  def handle_info({ref, :ok}, state) do
    # ignore result
    # demonitor and remove :DOWN message
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  # The task failed
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # ignore error
    {:noreply, state}
  end
end
