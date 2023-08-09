defmodule Snappy do
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "snappy"

  def decompress(stream) do
    stream
    |> Enum.into("")
    |> decompress_bytes()
  end

  defp decompress_bytes(_bytes), do: :erlang.nif_error(:nif_not_loaded)
end
