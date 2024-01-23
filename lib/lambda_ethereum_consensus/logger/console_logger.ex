defmodule ConsoleLogger do
  @moduledoc """
  Custom logger formatter for console output.
  """

  @pattern Logger.Formatter.compile(" $time $message ")

  def format(level, message, timestamp, metadata) do
    formatted_metadata = format_metadata(metadata)

    [format_level(level)] ++
      [Logger.Formatter.format(@pattern, level, message, timestamp, [])] ++
      [formatted_metadata] ++ ["\n"]
  rescue
    err ->
      inspect(err)
  end

  defp level_color(:info), do: :green
  defp level_color(:warning), do: :yellow
  defp level_color(:error), do: :red
  defp level_color(_), do: :default

  defp format_level(level) do
    upcased = level |> Atom.to_string() |> String.upcase()
    IO.ANSI.format([level_color(level), upcased])
  end

  def format_metadata(metadata) do
    Enum.map_join(
      metadata,
      " ",
      fn {key, value} ->
        IO.ANSI.format([
          :bright,
          Atom.to_string(key),
          :reset,
          "=" <> format_metadata_value(key, value)
        ])
      end
    )
  end

  def format_metadata_value(:root, root) do
    encoded = root |> Base.encode16(case: :lower)
    # get the first 3 and last 4 characters
    "0x#{String.slice(encoded, 0, 3)}..#{String.slice(encoded, -4, 4)}"
  end

  def format_metadata_value(:slot, slot) do
    Integer.to_string(slot)
  end
end
