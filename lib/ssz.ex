defmodule Ssz do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  ##### Functional wrappers
  @spec to_ssz(struct | list(struct)) :: {:ok, binary} | {:error, String.t()}
  def to_ssz(map)

  def to_ssz(%name{} = map), do: to_ssz_typed(map, name)

  def to_ssz([]) do
    # Type isn't used in this case
    to_ssz_rs([], SszTypes.ForkData)
  end

  def to_ssz([%name{} | _tail] = list) do
    to_ssz_typed(list, name)
  end

  @spec to_ssz_typed(term, module) :: {:ok, binary} | {:error, String.t()}
  def to_ssz_typed(term, schema) do
    term
    |> encode()
    |> to_ssz_rs(schema)
  end

  @spec from_ssz(binary, module) :: {:ok, struct} | {:error, String.t()}
  def from_ssz(bin, schema) do
    with {:ok, map} <- from_ssz_rs(bin, schema) do
      {:ok, decode(map)}
    end
  end

  @spec list_from_ssz(binary, module) :: {:ok, struct} | {:error, String.t()}
  def list_from_ssz(bin, schema) do
    with {:ok, list} <- list_from_ssz_rs(bin, schema) do
      {:ok, decode(list)}
    end
  end

  @spec hash_tree_root(struct) :: {:ok, SszTypes.root()} | {:error, String.t()}
  def hash_tree_root(map)

  def hash_tree_root(%name{} = map) do
    map
    |> encode()
    |> hash_tree_root_rs(name)
  end

  @spec hash_list_tree_root(list(struct), integer) ::
          {:ok, SszTypes.root()} | {:error, String.t()}
  def hash_list_tree_root(list, max_size)

  def hash_list_tree_root([], max_size) do
    # Type isn't used in this case
    hash_tree_root_list_rs([], max_size, SszTypes.ForkData)
  end

  def hash_list_tree_root([%name{} | _tail] = list, max_size) do
    hash_list_tree_root_typed(list, max_size, name)
  end

  @spec hash_list_tree_root_typed(list(struct), integer, module) ::
          {:ok, binary} | {:error, String.t()}
  def hash_list_tree_root_typed(list, max_size, schema) do
    list
    |> encode()
    |> hash_tree_root_list_rs(max_size, schema)
  end

  @spec hash_vector_tree_root_typed(list(struct), integer, module) ::
          {:ok, binary} | {:error, String.t()}
  def hash_vector_tree_root_typed(vector, max_size, schema) do
    vector
    |> encode()
    |> hash_tree_root_vector_rs(max_size, schema)
  end

  ##### Rust-side function stubs
  @spec to_ssz_rs(map | list, module, module) :: {:ok, binary} | {:error, String.t()}
  def to_ssz_rs(_term, _schema, _config \\ ChainSpec.get_config()), do: error()

  @spec from_ssz_rs(binary, module, module) :: {:ok, struct} | {:error, String.t()}
  def from_ssz_rs(_bin, _schema, _config \\ ChainSpec.get_config()), do: error()

  @spec list_from_ssz_rs(binary, module, module) :: {:ok, list(struct)} | {:error, String.t()}
  def list_from_ssz_rs(_bin, _schema, _config \\ ChainSpec.get_config()), do: error()

  @spec hash_tree_root_rs(map, module, module) :: {:ok, SszTypes.root()} | {:error, String.t()}
  def hash_tree_root_rs(_map, _schema, _config \\ ChainSpec.get_config()), do: error()

  @spec hash_tree_root_list_rs(list, integer, module, module) ::
          {:ok, SszTypes.root()} | {:error, String.t()}
  def hash_tree_root_list_rs(_list, _max_size, _schema, _config \\ ChainSpec.get_config()),
    do: error()

  @spec hash_tree_root_vector_rs(list, integer, module, module) ::
          {:ok, SszTypes.root()} | {:error, String.t()}
  def hash_tree_root_vector_rs(_vector, _max_size, _schema, _config \\ ChainSpec.get_config()),
    do: error()

  ##### Utils
  defp error, do: :erlang.nif_error(:nif_not_loaded)

  # Ssz types can have special decoding rules defined in their optional encode/1 function,
  defp encode(%name{} = struct) do
    if exported?(name, :encode, 1) do
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
    if exported?(name, :decode, 1) do
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

  defp exported?(module, function, arity) do
    Code.ensure_loaded!(module)
    function_exported?(module, function, arity)
  end

  @spec encode_u256(non_neg_integer) :: binary
  def encode_u256(num) do
    num
    |> :binary.encode_unsigned(:little)
    |> String.pad_trailing(32, <<0>>)
  end

  @spec decode_u256(binary) :: non_neg_integer
  def decode_u256(num), do: :binary.decode_unsigned(num, :little)
end
