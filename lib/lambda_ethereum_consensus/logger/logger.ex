defmodule ConsoleLogger do
  @moduledoc """
  Custom logger formatter for console output.
  """

  def format(level, message, timestamp, metadata) do
    pattern = Logger.Formatter.compile(" $time $message ")

    formatted_metadata =
      Enum.map_join(
        metadata,
        " ",
        fn {key, value} ->
          IO.ANSI.bright() <>
            Atom.to_string(key) <> IO.ANSI.reset() <> "=" <> format_metadata(key, value)
        end
      )

    [format_level(level)] ++
      [Logger.Formatter.format(pattern, level, message, timestamp, [])] ++
      [formatted_metadata] ++ ["\n"]
  rescue
    err ->
      inspect(err)
  end

  defp level_color(:info), do: IO.ANSI.green()
  defp level_color(:warning), do: IO.ANSI.yellow()
  defp level_color(:error), do: IO.ANSI.red()
  defp level_color(_), do: IO.ANSI.default_color()

  defp format_level(level) do
    upcased = level |> Atom.to_string() |> String.upcase()
    level_color(level) <> upcased <> IO.ANSI.reset()
  end

  def format_metadata(:root, root) do
    encoded = root |> Base.encode16(case: :lower)
    # get the first 3 and last 4 characters
    "0x#{String.slice(encoded, 0, 3)}..#{String.slice(encoded, -4, 4)}"
  end

  def format_metadata(:slot, slot) do
    Integer.to_string(slot)
  end
end
