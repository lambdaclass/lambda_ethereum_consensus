defmodule Ssz do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  ##### Functional wrappers
  @spec to_ssz(struct) :: {:ok, binary} | {:error, String.t()}
  def to_ssz(%name{} = map) do
    map
    |> encode()
    |> to_ssz_rs(name)
  end

  @spec from_ssz(binary, module) :: {:ok, struct} | {:error, String.t()}
  def from_ssz(bin, schema) do
    with {:ok, map} <- from_ssz_rs(bin, schema) do
      {:ok, decode(map)}
    end
  end

  ##### Rust-side function stubs
  @spec to_ssz_rs(map, module) :: {:ok, binary} | {:error, String.t()}
  def to_ssz_rs(_map, _schema), do: error()

  @spec from_ssz_rs(binary, module) :: {:ok, struct} | {:error, String.t()}
  def from_ssz_rs(_bin, _schema), do: error()

  ##### Utils
  defp error, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
    For Ssz types that have special encoding rules defined in their optional encode/1 function,
    call it recursively.
  """
  defp encode(%name{} = struct) do
    case function_exported?(name, :encode, 1) do
      true ->
        name.encode(struct)

      false ->
        struct
        |> Map.from_struct()
        |> Enum.map(fn {k, v} -> {k, encode(v)} end)
        |> then(&struct!(name, &1))
    end
  end

  defp encode(non_struct), do: non_struct

  @doc """
    For Ssz types that have special decoding rules defined in their optional decode/1 function,
    call it recursively.
  """
  defp decode(%name{} = struct) do
    case function_exported?(name, :decode, 1) do
      true ->
        name.decode(struct)

      false ->
        struct
        |> Map.from_struct()
        |> Enum.map(fn {k, v} -> {k, decode(v)} end)
        |> then(&struct!(name, &1))
    end
  end

  defp decode(non_struct), do: non_struct

  def encode_u256(num) do
    num
    |> :binary.encode_unsigned(:little)
    |> String.pad_trailing(32, <<0>>)
  end

  def decode_u256(num), do: :binary.decode_unsigned(num, :little)
end
