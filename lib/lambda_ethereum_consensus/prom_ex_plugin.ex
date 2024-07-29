defmodule LambdaEthereumConsensus.PromExPlugin do
  @moduledoc """
  This module defines our custom PromEx plugin.
  It contains all our custom metrics that are displayed on the `node` dashboard.
  """

  alias LambdaEthereumConsensus.Store.Db
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    buckets =
      Application.get_env(:lambda_ethereum_consensus, __MODULE__)
      |> Keyword.fetch!(:block_processing_buckets)

    [
      Event.build(:peer_metrics, [
        counter([:peers, :connection, :count], tags: [:result]),
        counter([:peers, :challenge, :count], tags: [:result]),
        counter([:network, :request, :count], tags: [:result, :type, :reason]),
        counter([:network, :pubsub_peers, :count], tags: [:result]),
        sum([:network, :pubsub_topic_active, :active], tags: [:topic]),
        counter([:network, :pubsub_topics_graft, :count], tags: [:topic]),
        counter([:network, :pubsub_topics_prune, :count], tags: [:topic]),
        counter([:network, :pubsub_topics_deliver_message, :count], tags: [:topic]),
        counter([:network, :pubsub_topics_duplicate_message, :count], tags: [:topic]),
        counter([:network, :pubsub_topics_reject_message, :count], tags: [:topic]),
        counter([:network, :pubsub_topics_un_deliverable_message, :count], tags: [:topic]),
        counter([:network, :pubsub_topics_validate_message, :count], tags: [:topic]),
        counter([:port, :message, :count], tags: [:function, :direction]),
        sum([:network, :request, :blocks], tags: [:result, :type, :reason])
      ]),
      Event.build(:sync_metrics, [
        last_value([:sync, :store, :slot], []),
        last_value([:sync, :on_block, :slot], []),
        distribution([:sync, :on_block, :stop, :duration],
          reporter_options: [buckets: buckets],
          unit: {:native, :millisecond}
        ),
        distribution([:sync, :on_block, :exception, :duration],
          reporter_options: [buckets: buckets],
          unit: {:native, :millisecond}
        )
      ]),
      Event.build(:db_metrics, [
        last_value([:db, :latency, :stop, :duration],
          unit: {:native, :millisecond},
          tags: [:module, :action]
        ),
        last_value([:db, :latency, :exception, :duration],
          unit: {:native, :millisecond},
          tags: [:module, :action]
        ),
        counter([:db, :latency, :stop, :count],
          unit: {:native, :millisecond},
          tags: [:module, :action]
        )
      ]),
      Event.build(:libp2pport_metrics, [
        last_value([:libp2pport, :handler, :stop, :duration],
          unit: {:native, :millisecond},
          tags: [:module, :action]
        ),
        last_value([:libp2pport, :handler, :exception, :duration],
          unit: {:native, :millisecond},
          tags: [:module, :action]
        ),
        counter([:libp2pport, :handler, :stop, :count],
          unit: {:native, :millisecond},
          tags: [:module, :action]
        )
      ]),
      Event.build(:forkchoice_metrics, [
        last_value([:fork_choice, :latency, :stop, :duration],
          unit: {:native, :millisecond},
          tags: [:handler, :transition, :operation]
        ),
        last_value([:fork_choice, :recompute_head, :stop, :duration],
          unit: {:native, :millisecond}
        ),
        last_value([:fork_choice, :recompute_head, :exception, :duration],
          unit: {:native, :millisecond}
        )
      ]),
      Event.build(:blocks_status, [
        last_value([:blocks, :status, :total],
          tags: [:id, :mainstat, :color, :title, :detail__root]
        ),
        last_value([:blocks, :relationship, :total],
          tags: [:id, :source, :target]
        )
      ])
    ]
  end

  @impl true
  def polling_metrics(_opts) do
    [
      Polling.build(:periodic_measurements, 15_000, {__MODULE__, :periodic_measurements, []}, [
        last_value([:db, :size, :total], unit: :byte),
        last_value([:vm, :message_queue, :length], tags: [:process])
      ])
    ]
  end

  def periodic_measurements() do
    message_queue_lengths()
    db_size()
  end

  def db_size() do
    db_size = Db.size()
    :telemetry.execute([:db, :size], %{total: db_size})
  end

  defp register_queue_length(name, len) do
    :telemetry.execute([:vm, :message_queue], %{length: len}, %{process: inspect(name)})
  end

  def message_queue_lengths() do
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
