defmodule LambdaEthereumConsensus.ForkChoice.Handlers do
  @moduledoc """
  Handlers that update the fork choice store.
  """

  def on_tick(store, _time) do
    {:ok, store}
  end

  def on_block(store, _block) do
    {:ok, store}
  end
end
