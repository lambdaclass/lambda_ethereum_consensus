defmodule LambdaEthereumConsensus.Ssz do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  @spec to_ssz(atom, map) :: {:ok, binary} | {:error, String.t()}
  def to_ssz(_schema, _map), do: error()

  @spec from_ssz(binary) :: {:ok, map} | {:error, String.t()}
  def from_ssz(_bin), do: error()

  defp error, do: :erlang.nif_error(:nif_not_loaded)
end
