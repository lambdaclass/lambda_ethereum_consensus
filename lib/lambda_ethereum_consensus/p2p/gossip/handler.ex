defmodule LambdaEthereumConsensus.P2P.Gossip.Handler do
  @moduledoc """
  Gossip handler behaviour
  """

  @callback handle_gossip_message(binary(), binary(), iodata()) :: :ok | {:error, any}
end
