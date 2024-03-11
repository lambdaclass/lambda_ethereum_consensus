defmodule Mix.Tasks.CheckEnabledTests do
  @moduledoc """
  A task that checks which spec-tests are enabled or skipped. Useful to make sure that desired
  tests are running.

  It traverses vector configs, forks and runners hierarchically.

  Run with MIX_ENV=test mix check_enabled_tests
  The output will be in a reports/spec_test_report.exs file, that can be formatted using mix format.
  """

  require Logger

  alias Spec.MetaUtils
  @output_dir "reports"

  def run(_args) do
    # TODO: pretty print.
    res = MetaUtils.check_enabled() |> inspect(limit: :infinity)
    File.mkdir_p!(@output_dir)
    File.write!(filename(), res)
    :ok
  end

  defp filename() do
    Path.join([@output_dir, "spec_test_report_#{timestamp_now()}.exs"])
  end

  defp timestamp_now(), do: DateTime.utc_now() |> Timex.format!("{YYYY}-{0M}-{0D}_{h24}-{m}-{s}")
end
