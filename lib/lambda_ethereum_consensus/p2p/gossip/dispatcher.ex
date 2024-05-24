defmodule LambdaEthereumConsensus.P2P.Gossip.Dispatcher do
  @moduledoc """
  Dispatch gossip messages to each module
  """

  alias LambdaEthereumConsensus.Store.Db

  @spec subscribe_to_topic(atom(), String.t()) :: :ok
  def subscribe_to_topic(module, topic) do
    Db.put(topic, Atom.to_string(module))
  end

  def dispatch_gossip(topic, msg_id, message) do
    {:ok, result_module} = Db.get(topic)
    module = String.to_atom(result_module)
    apply(module, :handle_gossip_message, [msg_id, message])
  end
end
