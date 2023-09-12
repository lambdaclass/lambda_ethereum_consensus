defmodule Snappy do
  @moduledoc """
  Snappy frame compression and decompression.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "snappy_nif"

  @spec decompress(binary) :: {:ok | :error, binary}
  def decompress(_bin), do: :erlang.nif_error(:nif_not_loaded)

  @spec compress(binary) :: {:ok | :error, binary}
  def compress(_bin), do: :erlang.nif_error(:nif_not_loaded)
end
