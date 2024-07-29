defmodule LambdaEthereumConsensus.PromEx do
  use PromEx, otp_app: :lambda_ethereum_consensus

  @impl true
  def plugins do
    [
      PromEx.Plugins.Beam,
      LambdaEthereumConsensus.PromExPlugin
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "beam.json"}
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "Prometheus"
    ]
  end
end
