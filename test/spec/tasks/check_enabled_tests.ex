defmodule Mix.Tasks.CheckEnabledTests do
  @moduledoc """
  A task that checks which spec-tests are enabled or skipped. Useful to make sure that desired
  tests are running.

  It traverses vector configs, forks and runners hierarchically.

  Run with `mix check_enabled_tests`
  The output will be a hierarchical list of full runs (✅), partial implementations (🟡) and
  skipped/unimplemented runners (❌).
  """

  use Mix.Task

  require Logger

  alias Spec.MetaUtils

  @impl Mix.Task
  def run(_args) do
    MetaUtils.check_enabled() |> print(0)
    :ok
  end

  defp print({name, report}, spaces) do
    print_spaced("🟡 #{name}", spaces)
    new_spaces = spaces + 3
    print(report, new_spaces)
  end

  defp print(report, spaces) when is_map(report) do
    # This will be done later on.
    report |> Map.get(:full_run, []) |> print_full_run(spaces)
    report |> Map.get(:full_skip, []) |> print_full_skip(spaces)
    for f <- Map.get(report, :partial, []), do: print(f, spaces)
  end

  defp print_full_run(run_list, spaces) when is_list(run_list) do
    for f <- run_list, do: print_full_run(f, spaces)
  end

  defp print_full_run(number, spaces) when is_number(number) do
    print_full_run({"enabled", number}, spaces)
  end

  defp print_full_run({name, number}, spaces) when is_number(number) do
    print_result(name, number, "✅", spaces)
  end

  defp print_full_skip(run_list, spaces) when is_list(run_list) do
    for f <- run_list, do: print_full_skip(f, spaces)
  end

  defp print_full_skip(name, spaces) when is_binary(name), do: print_spaced("❌ #{name}", spaces)
  defp print_full_skip({name, number}, spaces), do: print_result(name, number, "❌", spaces)

  defp print_result(name, number, emoji, spaces) do
    print_spaced("#{emoji} #{name} (#{number})", spaces)
  end

  defp print_spaced(text, spaces), do: IO.puts(String.duplicate(" ", spaces) <> text)
end
