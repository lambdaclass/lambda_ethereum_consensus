defmodule LambdaEthereumConsensus.Ssz do
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  @spec to_ssz(map) :: binary
  def to_ssz(_map), do: error()

  @spec from_ssz(binary) :: map
  def from_ssz(_bin), do: error()

  defp error(), do: :erlang.nif_error(:nif_not_loaded)
end
