defmodule LambdaEthereumConsensus.Ssz do
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  @spec decode(binary, atom) :: binary
  def decode(_b64, _opt \\ :standard), do: error()

  @spec encode(binary, atom) :: binary
  def encode(_s, _opt \\ :standard), do: error()

  defp error(), do: :erlang.nif_error(:nif_not_loaded)
end
