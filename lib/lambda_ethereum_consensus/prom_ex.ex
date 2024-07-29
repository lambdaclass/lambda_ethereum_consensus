defmodule LambdaEthereumConsensus.PromEx do
  @moduledoc """
  This module integrates the PromEx library. It sets up PromEx plugins and pre-built dashboards for the node.
  """
  use PromEx, otp_app: :lambda_ethereum_consensus

  @impl true
  def plugins() do
    [
      PromEx.Plugins.Beam,
      LambdaEthereumConsensus.PromExPlugin
    ]
  end

  @impl true
  def dashboards() do
    [
      {:prom_ex, "beam.json"}
    ]
  end

  @impl true
  def dashboard_assigns() do
    [
      datasource_id: "Prometheus"
    ]
  end
end
