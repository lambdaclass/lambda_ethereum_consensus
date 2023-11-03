defmodule LambdaEthereumConsensus.Telemetry do
  @moduledoc """
  Telemetry module for the consensus node.
  """
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()},
      {TelemetryMetricsPrometheus, [metrics: metrics()]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      # summary("phoenix.endpoint.start.system_time",
      #   unit: {:native, :millisecond}
      # ),
      # summary("phoenix.endpoint.stop.duration",
      #   unit: {:native, :millisecond}
      # ),
      # summary("phoenix.router_dispatch.start.system_time",
      #   tags: [:route],
      #   unit: {:native, :millisecond}
      # ),
      # summary("phoenix.router_dispatch.exception.duration",
      #   tags: [:route],
      #   unit: {:native, :millisecond}
      # ),
      # summary("phoenix.router_dispatch.stop.duration",
      #   tags: [:route],
      #   unit: {:native, :millisecond}
      # ),
      # summary("phoenix.socket_connected.duration",
      #   unit: {:native, :millisecond}
      # ),
      # summary("phoenix.channel_join.duration",
      #   unit: {:native, :millisecond}
      # ),
      # summary("phoenix.channel_handled_in.duration",
      #   tags: [:event],
      #   unit: {:native, :millisecond}
      # ),

      # Peer metrics
      counter("peers.connection.count", tags: [:result]),
      counter("network.request.count", tags: [:result, :type, :reason]),

      # VM Metrics
      ## Memory
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.memory.processes", unit: :byte),
      last_value("vm.memory.processes_used", unit: :byte),
      last_value("vm.memory.system", unit: :byte),
      last_value("vm.memory.atom", unit: :byte),
      last_value("vm.memory.atom_used", unit: :byte),
      last_value("vm.memory.binary", unit: :byte),
      last_value("vm.memory.code", unit: :byte),
      last_value("vm.memory.ets", unit: :byte),
      ## Scheduler run queue lengths
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io"),
      ## System counts
      last_value("vm.system_counts.process_count"),
      last_value("vm.system_counts.atom_count"),
      last_value("vm.system_counts.port_count")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {Module, :count, []}
    ]
  end
end
