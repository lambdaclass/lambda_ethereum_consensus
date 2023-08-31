defmodule Ssz do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  def to_ssz(%SszTypes.ExecutionPayload{} = map) do
    base_fee_per_gas =
      map.base_fee_per_gas
      |> :binary.encode_unsigned()
      |> String.pad_leading(32, <<0>>)

    map = Map.replace(map, :base_fee_per_gas, base_fee_per_gas)
    to_ssz(map, SszTypes.ExecutionPayload)
  end

  def to_ssz(%SszTypes.ExecutionPayloadHeader{} = map) do
    base_fee_per_gas =
      map.base_fee_per_gas
      |> :binary.encode_unsigned()
      |> String.pad_leading(32, <<0>>)

    map = Map.replace(map, :base_fee_per_gas, base_fee_per_gas)
    to_ssz(map, SszTypes.ExecutionPayloadHeader)
  end

  def to_ssz(%name{} = map), do: to_ssz(map, name)

  def to_ssz(_map, _schema), do: error()

  def from_ssz_raw(_bin, _schema), do: error()

  def from_ssz(bin, SszTypes.ExecutionPayload) do
    case from_ssz_raw(bin, SszTypes.ExecutionPayload) do
      {:ok, result} ->
        {:ok,
         Map.replace(result, :base_fee_per_gas, :binary.decode_unsigned(result.base_fee_per_gas))}

      x ->
        x
    end
  end

  def from_ssz(bin, SszTypes.ExecutionPayloadHeader) do
    case from_ssz_raw(bin, SszTypes.ExecutionPayloadHeader) do
      {:ok, result} ->
        {:ok,
         Map.replace(result, :base_fee_per_gas, :binary.decode_unsigned(result.base_fee_per_gas))}

      x ->
        x
    end
  end

  def from_ssz(bin, schema), do: from_ssz_raw(bin, schema)

  defp error, do: :erlang.nif_error(:nif_not_loaded)
end
