defmodule LambdaEthereumConsensus.Utils do
  @moduledoc """
  Set of utility functions used throughout the project
  """

  use Tesla
  alias LambdaEthereumConsensus.Calls

  @doc """
  Syncs the node using an inputed checkpoint
  """
  def sync_from_checkpoint(url) do
    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"Accept", "application/octet-stream"}]}
      ])

    with {:ok, result} <- Calls.get_call(url, client) do
      result
    end
  end
end
