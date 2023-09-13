defmodule Ssz do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  ##### Functional wrappers
  @spec to_ssz(struct, module) :: {:ok, binary} | {:error, String.t()}
  def to_ssz(%name{} = map, config \\ MainnetConfig) do
    map
    |> encode()
    |> to_ssz_rs(name, config)
  end

  @spec from_ssz(binary, module, module) :: {:ok, struct} | {:error, String.t()}
  def from_ssz(bin, schema, config \\ MainnetConfig) do
    with {:ok, map} <- from_ssz_rs(bin, schema, config) do
      {:ok, decode(map)}
    end
  end

  @spec hash_tree_root(struct, module) :: {:ok, binary} | {:error, String.t()}
  def hash_tree_root(%name{} = map, config \\ MainnetConfig) do
    map
    |> encode()
    |> hash_tree_root_rs(name, config)
  end

  ##### Rust-side function stubs
  @spec to_ssz_rs(map, module, module) :: {:ok, binary} | {:error, String.t()}
  def to_ssz_rs(_map, _schema, _config), do: error()

  @spec from_ssz_rs(binary, module, module) :: {:ok, struct} | {:error, String.t()}
  def from_ssz_rs(_bin, _schema, _config), do: error()

  @spec hash_tree_root_rs(map, module, module) :: {:ok, binary} | {:error, String.t()}
  def hash_tree_root_rs(_map, _schema, _config), do: error()

  ##### Utils
  defp error, do: :erlang.nif_error(:nif_not_loaded)

  # Ssz types can have special decoding rules defined in their optional encode/1 function,
  defp encode(%name{} = struct) do
    if function_exported?(name, :encode, 1) do
      name.encode(struct)
    else
      struct
      |> Map.from_struct()
      |> Enum.map(fn {k, v} -> {k, encode(v)} end)
      |> then(&struct!(name, &1))
    end
  end

  defp encode(non_struct), do: non_struct

  # Ssz types can have special decoding rules defined in their optional decode/1 function,
  defp decode(%name{} = struct) do
    if function_exported?(name, :decode, 1) do
      name.decode(struct)
    else
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
