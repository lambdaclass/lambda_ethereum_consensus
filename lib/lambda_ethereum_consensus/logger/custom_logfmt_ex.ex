defmodule CustomLogfmtEx do
  @moduledoc """
  Custom logger formatter for logfmt output.
  """

  alias LambdaEthereumConsensus.Utils

  def format(level, message, timestamp, metadata) do
    formatted_metadata = format_metadata(metadata)

    LogfmtEx.format(level, message, timestamp, formatted_metadata)
  end

  defp format_metadata(metadata) do
    metadata
    |> Keyword.replace_lazy(:root, &Utils.format_shorten_binary(&1))
    |> Keyword.replace_lazy(:bits, &Utils.format_bitstring(&1))
  end
end
