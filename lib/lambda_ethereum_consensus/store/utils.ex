defmodule LambdaEthereumConsensus.Store.Utils do
  defp get_key(prefix, suffix) when is_integer(suffix) do
    prefix <> :binary.encode_unsigned(suffix)
  end

  defp get_key(prefix, suffix) when is_binary(suffix) do
    prefix <> suffix
  end
end
