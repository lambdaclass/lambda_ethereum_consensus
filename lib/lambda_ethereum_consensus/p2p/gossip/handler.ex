defmodule LambdaEthereumConsensus.P2P.Gossip.Handler do
  @moduledoc """
  Gossip handler behaviour
  """
  alias Types.Store

  @callback handle_gossip_message(Store.t(), binary(), binary(), iodata()) ::
              {:ok, Store.t()} | {:error, any}
end
