defmodule Ssz do
  @moduledoc """
  SimpleSerialize (SSZ) serialization and deserialization.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "ssz_nif"

  ##### Functional wrappers
  @spec to_ssz(struct | list(struct)) :: {:ok, binary} | {:error, String.t()}
  def to_ssz(map)

  def to_ssz(%SszTypes.Checkpoint{} = container), do: serialize(container)
  def to_ssz(%SszTypes.Deposit{} = container), do: serialize(container)
  def to_ssz(%SszTypes.DepositData{} = container), do: serialize(container)
  def to_ssz(%SszTypes.DepositMessage{} = container), do: serialize(container)

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
    deserialize(bin, schema)
  end

  def from_ssz(bin, SszTypes.Deposit = schema) do
    deserialize(bin, schema)
  end

  def from_ssz(bin, SszTypes.DepositData = schema) do
    deserialize(bin, schema)
  end

  def from_ssz(bin, SszTypes.DepositMessage = schema) do
    deserialize(bin, schema)
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

  ### ENCODE ######
  def serialize(%struct{} = map), do: serialize(map, %{type: :container, schema: struct})

  def serialize(elements) when is_list(elements) do
    serialized =
      elements
      |> Enum.map(fn element ->
        {:ok, serialized} = serialize(element)
        serialized
      end)
      |> :binary.list_to_bin()

    {:ok, serialized}
  end

  def serialize(value) when is_binary(value), do: {:ok, value}

  def serialize(map, %{type: :container, schema: schema}) do
    schemas = schema.schema()

    serialized =
      schemas
      |> Enum.map(fn schema ->
        key = Enum.at(Map.keys(schema), 0)
        metadata = Map.get(schema, key)
        value = Map.get(map, key)
        {:ok, serialized} = serialize(value, metadata)
        serialized
      end)
      |> :binary.list_to_bin()

    {:ok, serialized}
  end

  def serialize(value, []) when is_binary(value), do: {:ok, value}

  def serialize(elements, %{type: :vector, schema: schema, max_size: max_size} = container) do
    if length(elements) > max_size do
      {:error, "max_size_error"}
    else
      serialize_list(elements, schema, container)
    end
  end

  # TODO check max_size of variable list
  def serialize(elements, %{type: :list, schema: schema, max_size: max_size} = container) do
    serialize_list(elements, schema, container)
  end

  def serialize(value, %{type: :uint, size: size}) when is_integer(value),
    do: serialize_uint(value, size)

  def serialize(value, %{type: :bytes}), do: {:ok, value}

  def serialize(value, %{} = schema),
    do: {:error, "Unknown schema: #{inspect(schema)} for value #{inspect(value)}"}

  @spec serialize_list(list, map, map) :: {:ok, binary} | {:error, String.t()}
  def serialize_list(elements, schema, container) when is_list(elements) do
    fixed_parts =
      elements
      |> Enum.map(fn element ->
        if is_variable_size(container), do: nil, else: serialize(element, schema)
      end)
      |> Enum.map(fn
        {:ok, ser} -> ser
        nil -> nil
      end)

    variable_parts =
      elements
      |> Enum.map(fn element ->
        if is_variable_size(container), do: serialize(element, schema), else: <<>>
      end)
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

    if Enum.sum(fixed_lengths ++ variable_lengths) <
         2 ** (@bytes_per_length_offset * @bits_per_byte) do
      variable_offsets =
        0..(length(elements) - 1)
        |> Enum.map(fn i ->
          slice_variable_lengths = Enum.take(variable_lengths, i)
          sum = Enum.sum(fixed_lengths ++ slice_variable_lengths)
          serialize_uint(sum, 32)
        end)
        |> Enum.map(fn {:ok, ser} -> ser end)

      fixed_parts = get_fixed_parts(fixed_parts, variable_offsets)

      final_ssz =
        (fixed_parts ++ variable_parts)
        |> :binary.list_to_bin()

      {:ok, final_ssz}
    else
      {:error, "invalid lengths"}
    end
  end

  @spec get_fixed_parts(list, list) :: list
  defp get_fixed_parts(fixed_parts, variable_offsets) do
    fixed_parts
    |> Enum.with_index()
    |> Enum.map(fn {part, index} ->
      if part != nil, do: part, else: Enum.at(variable_offsets, index)
    end)
  end

  defp serialize_uint(value, size) do
    <<encoded::binary-size(div(size, 8)), _rest::binary>> =
      value
      |> :binary.encode_unsigned(:little)
      |> String.pad_trailing(div(size, 8), <<0>>)

    {:ok, encoded}
  end

  ### DECODE ######
  @spec deserialize(binary, module) :: {:ok, struct} | {:error, String.t()}
  def deserialize(bin, schema) do
    schema_def = schema.schema()

    if is_list(schema_def) do
      {:ok, {_rest, items, _, _}} =
        schema_def
        |> Enum.reduce_while({:ok, {bin, %{}, [], 0}}, fn s,
                                                          {:ok,
                                                           {rest_bytes, items, offsets,
                                                            position_bin}} ->
          key = Enum.at(Map.keys(s), 0)
          metadata = Map.get(s, key)
          deserialize_with_acc(metadata, key, rest_bytes, items, offsets, position_bin)
        end)

      {:ok, struct!(schema, items)}
    else
      {:error, "Invalid container schema: #{inspect(schema_def)}"}
    end
  end

  @spec deserialize_with_acc(map, atom, binary, map, list, integer()) ::
          {:cont, {:ok, {binary, %{}}}} | {:halt, {:error, String.t()}}
  defp deserialize_with_acc(schema, key, rest_bytes, items, offsets, position_bin) do
    case deserialize_match(rest_bytes, schema) do
      {:ok, {decoded, rest, pos}} ->
        {:cont, {:ok, {rest, Map.merge(items, %{key => decoded}), offsets, position_bin + pos}}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  @spec deserialize_match(binary, %{}) :: {:ok, {any, binary, integer()}} | {:error, String.t()}
  defp deserialize_match(rest_bytes, schema) do
    case schema do
      %{type: :vector, schema: elements_schema, max_size: max_size} ->
        %{size: element_size} = elements_schema
        <<elements::binary-size(max_size * element_size), rest::bitstring>> = rest_bytes

        decoded_list =
          :binary.bin_to_list(elements)
          |> Enum.chunk_every(element_size)
          |> Enum.map(fn c -> :binary.list_to_bin(c) end)

        {:ok, {decoded_list, rest, max_size * element_size}}

      %{type: :list, schema: elements_schema, max_size: _max_size} ->
        with {:ok, decoded} <- list_from_ssz_elixir(rest_bytes, schema) do
          {:ok, {decoded, rest_bytes, 0}}
        end

      %{type: :container, schema: schema} ->
        with {:ok, decoded} <- deserialize(rest_bytes, schema) do
          {:ok, {decoded, rest_bytes, 0}}
        end

      %{type: :bytes, size: size} ->
        <<element::binary-size(size), rest::bitstring>> = rest_bytes
        {:ok, {element, rest, 0}}

      %{type: :bytes} ->
        {:ok, {rest_bytes, <<>>, 0}}

      %{type: :uint, size: size} ->
        <<element::integer-size(size)-little, rest::bitstring>> = rest_bytes
        {:ok, {element, rest, 0}}

      unknown_schema ->
        {:halt, {:error, "Unknown schema: #{inspect(unknown_schema)}"}}
    end
  end

  @spec list_from_ssz_elixir(binary, map | module) :: {:ok, list} | {:error, String.t()}
  def list_from_ssz_elixir(bin, schema) do
    if is_variable_schema(schema) do
      decode_list_of_variable_length_items(bin, schema.schema())
    else
      ssz_fixed_len =
        schema.schema
        |> Enum.map(fn schema ->
          key = Enum.at(Map.keys(schema), 0)
          metadata = Map.get(schema, key)
          byte_size_from_type(metadata)
        end)
        |> Enum.sum()

      decoded_list =
        :binary.bin_to_list(bin)
        |> Enum.chunk_every(ssz_fixed_len)
        |> Enum.map(fn c -> :binary.list_to_bin(c) end)
        |> Enum.map(fn b ->
          with {:ok, decoded} <- deserialize(b, schema) do
            decoded
          end
        end)

      {:ok, decoded_list}
    end
  end

  # based on sigp/ethereum_ssz::decode_list_of_variable_length_items
  @spec decode_list_of_variable_length_items(binary, module) ::
          {:ok, list} | {:error, String.t()}
  def decode_list_of_variable_length_items(bin, schema) do
    if byte_size(bin) == 0 do
      {:error, "Error trying to collect empty list"}
    else
      <<first_offset::integer-32-little, rest_bytes::bitstring>> = bin
      num_items = div(first_offset, @bytes_per_length_offset)

      if Integer.mod(first_offset, @bytes_per_length_offset) != 0 ||
           first_offset < @bytes_per_length_offset do
        {:error, "InvalidListFixedBytesLen"}
      else
        with {:ok, first_offset} <-
               sanitize_offset(first_offset, nil, byte_size(bin), first_offset) do
          {:ok, {decoded_list, _, _}} =
            decode_variable_list(first_offset, rest_bytes, num_items, bin, schema.schema())

          {:ok, decoded_list |> Enum.reverse()}
        end
      end
    end
  end

  @spec decode_variable_list(integer(), binary, integer(), binary, map) ::
          {:ok, {list, integer(), binary}} | {:error, String.t()}
  defp decode_variable_list(first_offset, rest_bytes, num_items, bin, schema) do
    1..num_items
    |> Enum.reduce_while({:ok, {[], first_offset, rest_bytes}}, fn i,
                                                                   {:ok,
                                                                    {acc_decoded, offset,
                                                                     acc_rest_bytes}} ->
      if i == num_items do
        part = :binary.part(bin, offset, byte_size(bin) - offset)

        with {:ok, {decoded, rest_bytes, pos}} <- deserialize_match(part, schema) do
          {:cont, {:ok, {[decoded | acc_decoded], offset, rest_bytes}}}
        end
      else
        get_next_offset(acc_decoded, acc_rest_bytes, schema, offset, bin, first_offset)
      end
    end)
  end

  @spec get_next_offset(list, binary, map, integer(), binary, integer()) ::
          {:cont, {:ok, {list, integer(), binary}}} | {:halt, {:error, String.t()}}
  defp get_next_offset(acc_decoded, acc_rest_bytes, schema, offset, bin, first_offset) do
    <<next_offset::integer-32-little, rest_bytes::bitstring>> = acc_rest_bytes

    case sanitize_offset(next_offset, offset, byte_size(bin), first_offset) do
      {:ok, next_offset} ->
        part = :binary.part(bin, offset, next_offset - offset)

        with {:ok, {decoded, _, _}} <- deserialize_match(part, schema) do
          {:cont, {:ok, {[decoded | acc_decoded], next_offset, rest_bytes}}}
        end

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  ##### HELPERS ##########
  defp is_variable_schema(%{type: :list}), do: true

  defp is_variable_schema(map) when is_list(map) do
    map
    |> Enum.map(fn schema ->
      key = Enum.at(Map.keys(schema), 0)
      metadata = Map.get(schema, key)
      is_variable_size(metadata)
    end)
    |> Enum.all?()
  end

  defp is_variable_schema(map) do
    if exported?(map, :schema, 0) do
      is_variable_schema(map.schema())
    end
  end

  defp byte_size_from_type(%{type: :uint, size: size}), do: div(size, @bits_per_byte)
  defp byte_size_from_type(%{type: :bytes, size: size}), do: size

  defp is_variable_size(%struct{} = map) when is_struct(map) do
    schema = struct.schema()

    schema
    |> Enum.map(fn schema ->
      key = Enum.at(Map.keys(schema), 0)
      metadata = Map.get(schema, key)
      is_variable_size(metadata)
    end)
    |> Enum.all?()
  end

  defp is_variable_size(%{type: :container, schema: schema}) do
    schema
    |> Enum.map(fn schema ->
      key = Enum.at(Map.keys(schema), 0)
      metadata = Map.get(schema, key)
      is_variable_size(metadata)
    end)
    |> Enum.all?()
  end

  defp is_variable_size(%{type: :list}), do: true
  defp is_variable_size(%{type: :vector}), do: false
  defp is_variable_size(%{type: :bytes}), do: true
  defp is_variable_size(%{type: :uint}), do: false

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
