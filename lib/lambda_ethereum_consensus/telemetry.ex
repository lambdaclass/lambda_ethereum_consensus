defmodule LambdaEthereumConsensus.Telemetry do
  @moduledoc """
  Telemetry module for the consensus node.
  """
  use Supervisor
  import Telemetry.Metrics

  @block_time_ms 12_000
  @block_processing_buckets [0.5, 1.0, 1.5, 2, 4, 6, 8] |> Enum.map(&(&1 * @block_time_ms))

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 15_000},
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
      counter("peers.challenge.count", tags: [:result]),
      counter("network.request.count", tags: [:result, :type, :reason]),
      counter("network.pubsub_peers.count", tags: [:result]),
      sum("network.pubsub_topic_active.active", tags: [:topic]),
      counter("network.pubsub_topics_graft.count", tags: [:topic]),
      counter("network.pubsub_topics_prune.count", tags: [:topic]),
      counter("network.pubsub_topics_deliver_message.count", tags: [:topic]),
      counter("network.pubsub_topics_duplicate_message.count", tags: [:topic]),
      counter("network.pubsub_topics_reject_message.count", tags: [:topic]),
      counter("network.pubsub_topics_un_deliverable_message.count", tags: [:topic]),
      counter("network.pubsub_topics_validate_message.count", tags: [:topic]),
      counter("port.message.count", tags: [:function, :direction]),
      sum("network.request.blocks", tags: [:result, :type, :reason]),

      # Sync metrics
      last_value("sync.store.slot"),
      last_value("sync.on_block.slot"),
      distribution("sync.on_block.stop.duration",
        reporter_options: [buckets: @block_processing_buckets],
        unit: {:native, :millisecond}
      ),
      distribution("sync.on_block.exception.duration",
        reporter_options: [buckets: @block_processing_buckets],
        unit: {:native, :millisecond}
      ),

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
      last_value("vm.system_counts.port_count"),
      last_value("vm.message_queue.length", tags: [:process])
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      {__MODULE__, :message_queue_lengths, []}
    ]
  end

  defp register_queue_length(name, len) do
    :telemetry.execute([:vm, :message_queue], %{length: len}, %{process: inspect(name)})
  end

  def message_queue_lengths do
    Process.list()
    |> Enum.each(fn pid ->
      case Process.info(pid, [:message_queue_len, :registered_name]) do
        [message_queue_len: len, registered_name: name] -> register_queue_length(name, len)
        [message_queue_len: len] -> register_queue_length(pid, len)
        _ -> nil
      end
    end)
  end
end
