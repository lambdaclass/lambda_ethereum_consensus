defmodule Ssz do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  ##### Functional wrappers
  def to_ssz(%name{} = map) do
    map
    |> encode()
    |> to_ssz_rs(name)
  end

  def from_ssz(bin, schema) do
    with {:ok, map} <- from_ssz_rs(bin, schema) do
      {:ok, decode(map)}
    end
  end

  ##### Rust-side function stubs
  def to_ssz_rs(_map, _schema), do: error()

  def from_ssz_rs(_bin, _schema), do: error()

  ##### Utils
  defp error, do: :erlang.nif_error(:nif_not_loaded)

  defp encode(%SszTypes.ExecutionPayloadHeader{} = map) do
    Map.update!(map, :base_fee_per_gas, &encode_u256/1)
  end

  defp encode(%SszTypes.ExecutionPayload{} = map) do
    Map.update!(map, :base_fee_per_gas, &encode_u256/1)
  end

  defp encode(map), do: map

  defp encode_u256(num) do
    num
    |> :binary.encode_unsigned(:little)
    |> String.pad_trailing(32, <<0>>)
  end

  defp decode(%SszTypes.ExecutionPayloadHeader{} = map) do
    Map.update!(map, :base_fee_per_gas, &decode_u256/1)
  end

  defp decode(%SszTypes.ExecutionPayload{} = map) do
    Map.update!(map, :base_fee_per_gas, &decode_u256/1)
  end

  defp decode(map), do: map

  defp decode_u256(num), do: :binary.decode_unsigned(num, :little)
end
