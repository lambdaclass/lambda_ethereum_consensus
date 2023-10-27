defmodule Ssz do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  ##### Functional wrappers
  @spec to_ssz(struct | list(struct)) :: {:ok, binary} | {:error, String.t()}
  def to_ssz(map)

  def to_ssz(%SszTypes.Checkpoint{} = container), do: serialize(container)

  def to_ssz(%name{} = map), do: to_ssz_typed(map, name)

  def to_ssz([]) do
    # Type isn't used in this case
    to_ssz_rs([], SszTypes.ForkData)
  end

  def to_ssz([%SszTypes.VoluntaryExit{} | _tail] = list) do
    serialize(list)
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

  def from_ssz(bin, SszTypes.Checkpoint = schema) do
    {:ok, decode_elixir(bin, schema)}
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

  ##### elixir native ssz
  @bytes_per_length_offset 4
  @bytes_per_chunk 32
  @bits_per_byte 8

  defp is_variable_schema(%{} = map) when is_map(map) and map == %{}, do: true

  defp is_variable_schema(%{} = map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> is_variable_size({v, k}) end)
    |> Enum.all?()
  end

  defp ssz_fixed_len(%{} = map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> byte_size_from_type(v) end)
    |> Enum.sum()
  end

  defp byte_size_from_type(:uint64), do: 8
  defp byte_size_from_type(:bytes32), do: 32

  defp is_variable_size(element) when is_list(element), do: true

  defp is_variable_size(element) when is_struct(element) do
    element
    |> Map.from_struct()
    |> Enum.map(fn {_k, v} -> is_variable_size(v) end)
    |> Enum.all?()
  end

  defp is_variable_size(element) when is_integer(element), do: false
  defp is_variable_size(element) when is_boolean(element), do: false
  defp is_variable_size({:uint64, _value}), do: false
  defp is_variable_size({:bytes32, _value}), do: false

  # TODO bitlist is variable-length but bitvector is fixed-length
  defp is_variable_size(element) when is_bitstring(element), do: true
  defp is_variable_size(element) when is_binary(element), do: true

  defmacro is_uint8(value) do
    quote do: unquote(value) in 0..unquote(2 ** 8 - 1)
  end

  defmacro is_uint64(value) do
    quote do: unquote(value) in unquote(2 ** 8)..unquote(2 ** 64 - 1)
  end

  defmacro is_uint256(value) do
    quote do: unquote(value) in unquote(2 ** 64)..unquote(2 ** 256 - 1)
  end

  def serialize(%struct{} = map) do
    schema = struct.schema()

    values =
      map
      |> Map.from_struct()
      |> Enum.map(fn {k, v} ->
        {schema[k], v}
      end)

    # |> Enum.reverse()

    serialize(values)
  end

  def serialize(value) when is_list(value) do
    fixed_parts =
      value
      |> Enum.map(fn v -> if is_variable_size(v), do: nil, else: serialize(v) end)
      |> Enum.map(fn
        {:ok, ser} -> ser
        nil -> nil
      end)

    variable_parts =
      value
      |> Enum.map(fn v -> if is_variable_size(v), do: serialize(v), else: <<>> end)
      |> Enum.map(fn
        {:ok, ser} -> ser
        <<>> -> <<>>
      end)

    fixed_lengths =
      fixed_parts
      |> Enum.map(fn part ->
        if part != nil, do: byte_size(part), else: @bytes_per_length_offset
      end)

    variable_lengths =
      variable_parts
      |> Enum.map(fn part -> byte_size(part) end)

    variable_offsets =
      0..(length(value) - 1)
      |> Enum.map(fn i ->
        slice_variable_lengths = Enum.take(variable_lengths, i)
        sum = Enum.sum(fixed_lengths ++ slice_variable_lengths)
        serialize_uint(sum, 32)
      end)
      |> Enum.map(fn {:ok, ser} -> ser end)

    fixed_parts =
      fixed_parts
      |> Enum.with_index()
      |> Enum.map(fn {part, i} -> if part != nil, do: part, else: Enum.at(variable_offsets, i) end)

    final_ssz =
      (Enum.reverse(variable_parts) ++ Enum.reverse(fixed_parts))
      |> Enum.reduce(&<>/2)

    {:ok, final_ssz}
  end

  def serialize(value) when is_integer(value) and is_uint8(value), do: serialize_uint(value, 8)
  def serialize(value) when is_integer(value) and is_uint64(value), do: serialize_uint(value, 64)

  def serialize(value) when is_integer(value) and is_uint256(value),
    do: serialize_uint(value, 256)

  def serialize(value) when is_binary(value), do: {:ok, value}

  def serialize({:uint64, value}), do: serialize_uint(value, 64)

  def serialize({:bytes32, value}), do: {:ok, value}

  def serialize(value), do: {:error, "Unknown schema: #{inspect(value)}"}

  defp serialize_uint(value, size) do
    <<encoded::binary-size(div(size, 8))>> =
      value
      |> :binary.encode_unsigned(:little)
      |> String.pad_trailing(div(size, 8), <<0>>)

    {:ok, encoded}
  end

  @spec list_from_ssz_elixir(binary, module) :: {:ok, struct} | {:error, String.t()}
  def list_from_ssz_elixir(bin, schema) do
    if is_variable_schema(schema.schema) do
      decode_list_of_variable_length_items(bin, schema)
    else
      ssz_fixed_len = ssz_fixed_len(schema.schema)

      decoded_list =
        :binary.bin_to_list(bin)
        |> Enum.chunk_every(ssz_fixed_len)
        |> Enum.map(fn c -> :binary.list_to_bin(c) end)
        |> Enum.map(fn b -> decode_elixir(b, schema) end)

      {:ok, decoded_list}
    end
  end

  # based on sigp/ethereum_ssz::decode_list_of_variable_length_items
  @spec decode_list_of_variable_length_items(binary, module) ::
          {:ok, struct} | {:error, String.t()}
  def decode_list_of_variable_length_items(bin, schema) do
    if byte_size(bin) == 0 do
      {:error, "Error trying to collect empty list"}
    else
      <<first_offset::integer-32-little, rest::bitstring>> = bin
      num_items = div(first_offset, @bytes_per_length_offset)

      if Integer.mod(first_offset, @bytes_per_length_offset) != 0 ||
           first_offset < @bytes_per_length_offset do
        {:error, "InvalidListFixedBytesLen"}
      else
        with {:ok, first_offset} <-
               sanitize_offset(first_offset, nil, byte_size(bin), first_offset) do
          {:ok, {decoded_list, _, _}} =
            1..num_items
            |> Enum.reduce_while({:ok, {[], first_offset, rest}}, fn i,
                                                                     {:ok,
                                                                      {acc, offset, acc_rest}} ->
              if i == num_items do
                part = :binary.part(bin, offset, byte_size(bin) - offset)
                {:cont, {:ok, {[decode_elixir(part, schema) | acc], offset, rest}}}
              else
                <<next_offset::integer-32-little, rest::bitstring>> = acc_rest

                case sanitize_offset(next_offset, offset, byte_size(bin), first_offset) do
                  {:ok, next_offset} ->
                    part = :binary.part(bin, offset, next_offset - offset)
                    {:cont, {:ok, {[decode_elixir(part, schema) | acc], next_offset, rest}}}

                  {:error, error} ->
                    {:halt, {:error, error}}
                end
              end
            end)

          {:ok, decoded_list |> Enum.reverse()}
        end
      end
    end
  end

  def decode_elixir(bin, SszTypes.Transaction), do: bin

  def decode_elixir(bin, SszTypes.Checkpoint) do
    <<epoch::integer-64-little, root::binary-size(32)>> = bin
    struct!(SszTypes.Checkpoint, %{epoch: epoch, root: root})
  end

  def decode_elixir(bin, SszTypes.VoluntaryExit) do
    <<epoch::integer-64-little, validator_index::integer-64-little>> = bin
    struct!(SszTypes.VoluntaryExit, %{epoch: epoch, validator_index: validator_index})
  end

  def decode_elixir(_value, schema), do: {:error, "Unknown schema: #{inspect(schema)}"}

  # https://notes.ethereum.org/ruKvDXl6QOW3gnqVYb8ezA?view
  defp sanitize_offset(offset, previous_offset, num_bytes, num_fixed_bytes) do
    cond do
      offset < num_fixed_bytes ->
        {:error, "OffsetIntoFixedPortion"}

      previous_offset == nil && offset != num_fixed_bytes ->
        {:error, "OffsetSkipsVariableBytes"}

      offset > num_bytes ->
        {:error, "OffsetOutOfBounds"}

      previous_offset != nil && previous_offset > offset ->
        {:error, "OffsetsAreDecreasing"}

      true ->
        {:ok, offset}
    end
  end
end
