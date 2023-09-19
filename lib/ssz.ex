defmodule Ssz do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  ##### Functional wrappers
  @spec to_ssz(struct | list(struct), module) :: {:ok, binary} | {:error, String.t()}
  def to_ssz(map, config \\ MainnetConfig)

  def to_ssz(%name{} = map, config) do
    map
    |> encode()
    |> to_ssz_rs(name, config)
  end

  def to_ssz([], config) do
    # Type isn't used in this case
    to_ssz_rs([], SszTypes.ForkData, config)
  end

  def to_ssz([%name{} | _tail] = list, config) do
    list
    |> encode()
    |> to_ssz_rs(name, config)
  end

  @spec from_ssz(binary, module, module) :: {:ok, struct} | {:error, String.t()}
  def from_ssz(bin, schema, config \\ MainnetConfig) do
    with {:ok, map} <- from_ssz_rs(bin, schema, config) do
      {:ok, decode(map)}
    end
  end

  @spec list_from_ssz(binary, module, module) :: {:ok, struct} | {:error, String.t()}
  def list_from_ssz(bin, schema, config \\ MainnetConfig) do
    with {:ok, list} <- list_from_ssz_rs(bin, schema, config) do
      {:ok, decode(list)}
    end
  end

  @spec hash_tree_root(struct, module) :: {:ok, binary} | {:error, String.t()}
  def hash_tree_root(map, config \\ MainnetConfig)

  def hash_tree_root(%name{} = map, config) do
    map
    |> encode()
    |> hash_tree_root_rs(name, config)
  end

  @spec hash_list_tree_root(list(struct), integer, module) :: {:ok, binary} | {:error, String.t()}
  def hash_list_tree_root(list, max_size, config \\ MainnetConfig)

  def hash_list_tree_root([], max_size, config) do
    # Type isn't used in this case
    hash_tree_root_list_rs([], max_size, SszTypes.ForkData, config)
  end

  def hash_list_tree_root([%name{} | _tail] = list, max_size, config) do
    list
    |> encode()
    |> hash_tree_root_list_rs(max_size, name, config)
  end

  ##### Rust-side function stubs
  @spec to_ssz_rs(map | list, module, module) :: {:ok, binary} | {:error, String.t()}
  def to_ssz_rs(_term, _schema, _config), do: error()

  @spec from_ssz_rs(binary, module, module) :: {:ok, struct} | {:error, String.t()}
  def from_ssz_rs(_bin, _schema, _config), do: error()

  @spec list_from_ssz_rs(binary, module, module) :: {:ok, list(struct)} | {:error, String.t()}
  def list_from_ssz_rs(_bin, _schema, _config), do: error()

  @spec hash_tree_root_rs(map, module, module) :: {:ok, binary} | {:error, String.t()}
  def hash_tree_root_rs(_map, _schema, _config), do: error()

  @spec hash_tree_root_list_rs(list, integer, module, module) ::
          {:ok, binary} | {:error, String.t()}
  def hash_tree_root_list_rs(_list, _max_size, _schema, _config), do: error()

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

  defp encode(list) when is_list(list) do
    Enum.map(list, &encode/1)
  end

  defp encode(list) when is_list(list), do: list |> Enum.map(&encode/1)
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

  defp decode(list) when is_list(list), do: list |> Enum.map(&decode/1)
  defp decode(non_struct), do: non_struct

  @spec encode_u256(non_neg_integer) :: binary
  def encode_u256(num) do
    num
    |> :binary.encode_unsigned(:little)
    |> String.pad_trailing(32, <<0>>)
  end

  @spec decode_u256(binary) :: non_neg_integer
  def decode_u256(num), do: :binary.decode_unsigned(num, :little)
end
