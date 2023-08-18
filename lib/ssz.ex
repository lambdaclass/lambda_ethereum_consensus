defmodule Ssz do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  @spec to_ssz(struct) :: {:ok, binary} | {:error, String.t()}
  def to_ssz(%name{} = map), do: to_ssz(map, name)

  @spec to_ssz(map, atom) :: {:ok, binary} | {:error, String.t()}
  def to_ssz(_map, _schema), do: error()

  @spec from_ssz(binary, module) :: {:ok, struct} | {:error, String.t()}
  def from_ssz(_bin, _schema), do: error()

  defp error, do: :erlang.nif_error(:nif_not_loaded)
end
