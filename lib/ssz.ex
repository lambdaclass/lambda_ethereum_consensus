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

  def encode_poc(_map, _schema, _config \\ MainnetConfig), do: error()

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

  @spec encode_u256(non_neg_integer) :: binary
  def encode_u256(num) do
    num
    |> :binary.encode_unsigned(:little)
    |> String.pad_trailing(32, <<0>>)
  end

  @spec decode_u256(binary) :: non_neg_integer
  def decode_u256(num), do: :binary.decode_unsigned(num, :little)

  ##### PoC: basic type de/serializing
  def encode(value, schema)

  def encode(value, :uint8) when is_integer(value), do: encode(value, {:uint, 8})
  def encode(value, :uint16) when is_integer(value), do: encode(value, {:uint, 16})
  def encode(value, :uint32) when is_integer(value), do: encode(value, {:uint, 32})
  def encode(value, :uint64) when is_integer(value), do: encode(value, {:uint, 64})
  def encode(value, :uint128) when is_integer(value), do: encode(value, {:uint, 128})
  def encode(value, :uint256) when is_integer(value), do: encode(value, {:uint, 256})

  def encode(value, {:uint, size}) when is_integer(value) and is_integer(size) do
    <<encoded::little-unsigned-integer-size(size)>> = value

    {:ok, encoded}
  end

  def encode(value, :boolean) when is_boolean(value) do
    {:ok, if(value, do: "\x01", else: "\x00")}
  end

  def encode(%name{} = map, {:container, name}) when is_atom(name) do
    to_ssz(map)
  end

  def encode(value, {:list, sub_schema, max_size}) when is_list(value) do
    if length(value) > max_size do
      {:error, "max size exceeded"}
    else
      encode_list(value, sub_schema)
    end
  end

  def encode(value, {:vector, sub_schema, size}) when is_list(value) do
    if length(value) != size do
      {:error, "vector size mismatch"}
    else
      encode_list(value, sub_schema)
    end
  end

  def encode(_value, schema), do: {:error, "Unknown schema: #{inspect(schema)}"}

  defp encode_list(value, sub_schema) do
    value
    |> Stream.map(&encode(&1, sub_schema))
    |> Enum.reduce_while({:ok, []}, fn
      {:error, reason}, _ ->
        {:halt, {:error, reason}}

      {:ok, encoded}, {:ok, acc} ->
        {:cont, {:ok, {[acc, encoded]}}}
    end)
  end

  def decode(encoded, schema)

  def decode(encoded, :uint8), do: decode(encoded, {:uint, 8})
  def decode(encoded, :uint16), do: decode(encoded, {:uint, 16})
  def decode(encoded, :uint32), do: decode(encoded, {:uint, 32})
  def decode(encoded, :uint64), do: decode(encoded, {:uint, 64})
  def decode(encoded, :uint128), do: decode(encoded, {:uint, 128})
  def decode(encoded, :uint256), do: decode(encoded, {:uint, 256})

  def decode(<<num::little-unsigned-integer-size(size)>>, {:uint, size}) when is_integer(size) do
    {:ok, num}
  end

  def decode(encoded, :boolean) do
    case encoded do
      "\x01" -> {:ok, true}
      "\x00" -> {:ok, false}
    end
  end

  def encode(%name{} = map, {:container, name}) when is_atom(name) do
    from_ssz(map, name)
  end

  def decode(value, {:list, sub_schema, max_size}) when is_list(value) do
    if length(value) > max_size do
      {:error, "max size exceeded"}
    else
      encode_list(value, sub_schema)
    end
  end

  def decode(value, {:vector, sub_schema, size}) when is_list(value) do
    if length(value) != size do
      {:error, "vector size mismatch"}
    else
      encode_list(value, sub_schema)
    end
  end

  def decode(_encoded, schema), do: {:error, "Unknown schema: #{inspect(schema)}"}
end
