defmodule Utils.Date do
  @moduledoc """
  Module with date utilities to be shared across scripts and utilities.
  """
  alias Timex.Format.DateTime.Formatter

  @doc """
  Returns a human readable string representing the current UTC datetime. Specially useful to
  name auto-generated files.
  """
  def now_str() do
    DateTime.utc_now()
    |> Formatter.format!("{YYYY}_{0M}_{0D}__{h24}_{m}_{s}_{ss}")
    |> String.replace(".", "")
  end
end
