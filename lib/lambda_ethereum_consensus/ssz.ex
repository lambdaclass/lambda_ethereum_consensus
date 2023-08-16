defmodule LambdaEthereumConsensus.Ssz do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  @spec to_ssz(map) :: {:ok | :error , binary }
  def to_ssz(_map), do: error()

  @spec from_ssz(binary) :: {:ok | :error , map }
  def from_ssz(_bin), do: error()

  defp error, do: :erlang.nif_error(:nif_not_loaded)
end
