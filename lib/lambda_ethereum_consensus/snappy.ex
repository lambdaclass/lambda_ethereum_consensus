defmodule Snappy do
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "snappy"

  @spec decompress(binary) :: {:ok | :error, binary}
  def decompress(_bin), do: :erlang.nif_error(:nif_not_loaded)
end
