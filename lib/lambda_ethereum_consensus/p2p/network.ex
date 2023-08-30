defmodule LambdaEthereumConsensus.NetworkAgent do
  @moduledoc """
  Contains a pair of Host and PubSub handles.
  """
  use Agent

  def start_link(_opts) do
    Agent.start_link(
      &start_network/0,
      name: __MODULE__
    )
  end

  def start_network do
    {:ok, host} = Libp2p.host_new()
    {:ok, gsub} = Libp2p.new_gossip_sub(host)
    {host, gsub}
  end

  def get_host, do: Agent.get(__MODULE__, fn {host, _} -> host end)
  def get_gossipsub, do: Agent.get(__MODULE__, fn {_, gsub} -> gsub end)
end
