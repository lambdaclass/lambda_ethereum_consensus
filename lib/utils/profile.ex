defmodule LambdaEthereumConsensus.Profile do
  @moduledoc """
  Wrappers for profiling using EEP, with easy defaults.
  """
  alias Timex.Format.DateTime.Formatter
  @default_profile_time_millis 300

  @doc """
  Builds a simple profile trace. Always returns :ok. The trace output is in qcachegrind format.

  Optional arguments:
  - trace_name: the output file will be "callgrind.out.<trace_name>". If no name is given
    then the date (e.g. 2023_09_07__12_00_34_652201) will be used by default.
  - profile_time_millis: the amount of milliseconds in which the app will be instrumented and
    the profile will be taken. The more time, the more information in the trace, but the more
    pressure applied to the app (instrumentation makes everything slower). If the node is in
    production and already at a CPU limit, then the best is to take many short (e.g. 300ms)
    traces instead of a long one and to inspect them separately.
  """
  def build(opts \\ []) do
    trace_name = Keyword.get(opts, :trace_name, now_str())
    erlang_trace_name = String.to_charlist(trace_name)
    profile_time_millis = Keyword.get(opts, :profile_time_millis, @default_profile_time_millis)

    :eep.start_file_tracing(erlang_trace_name)
    :timer.sleep(profile_time_millis)
    :eep.stop_tracing()
    :eep.convert_tracing(erlang_trace_name)

    File.rm(trace_name <> ".trace")
    :ok
  end

  defp now_str() do
    DateTime.utc_now()
    |> Formatter.format!("{YYYY}_{0M}_{0D}__{h24}_{m}_{s}_{ss}")
    |> String.replace(".", "")
  end
end
