defmodule Mix.Tasks.CheckEnabledTests do
  @moduledoc """
  A task that checks which spec-tests are enabled or skipped. Useful to make sure that desired
  tests are running.

  It traverses vector configs, forks and runners hierarchically.
  """

  alias Spec.MetaUtils

  def run(_args) do
    # TODO: pretty print.
    MetaUtils.check_enabled() |> IO.inspect(limit: :infinity)
    :ok
  end
end
