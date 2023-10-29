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

  def from_ssz(bin, SszTypes.Deposit = schema) do
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

  ### ENCODE ######
  def serialize(%struct{} = map) when is_struct(map) do
    schema = struct.schema()

    values =
      schema
      |> Enum.map(fn schema ->
        key = Enum.at(Map.keys(schema), 0)
        metadata = Map.get(schema, key)
        value = Map.get(map, key)
        Map.merge(metadata, %{value: value})
      end)

    serialize(values)
  end

  def serialize(%{type: :struct, value: map, schema: schema}) do
    serialize(map)
  end

  def serialize(%{type: :list, value: elements, schema: schema, max_size: max_size}) do
    elements =
      elements
      |> Stream.map(fn value ->
        Map.merge(schema, %{value: value})
      end)
      |> Enum.to_list()

    serialize_list(elements)
  end

  def serialize(value) when is_list(value), do: serialize_list(value)

  def serialize(%{type: :uint, size: size, value: value}) when is_integer(value),
    do: serialize_uint(value, size)

  def serialize(value) when is_binary(value), do: {:ok, value}

  def serialize(%{type: :bytes, size: size, value: value}), do: {:ok, value}
  def serialize(%{} = schema), do: {:error, "Unknown schema: #{inspect(schema)}"}

  def serialize_list(elements) when is_list(elements) do
    fixed_parts =
      elements
      |> Enum.map(fn v ->
        if is_variable_size(v), do: nil, else: serialize(v)
      end)
      |> Enum.map(fn
        {:ok, ser} -> ser
        nil -> nil
      end)

    variable_parts =
      elements
      |> Enum.map(fn v ->
        if is_variable_size(v), do: serialize(v), else: <<>>
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

    variable_offsets =
      0..(length(elements) - 1)
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
      (fixed_parts ++ variable_parts)
      |> :binary.list_to_bin()

    {:ok, final_ssz}
  end

  defp serialize_uint(value, size) do
    <<encoded::binary-size(div(size, 8)), _rest::binary>> =
      value
      |> :binary.encode_unsigned(:little)
      |> String.pad_trailing(div(size, 8), <<0>>)

    {:ok, encoded}
  end

  ### DECODE ######
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

  def decode_elixir(bin, SszTypes.DepositData) do
    <<pubkey::binary-size(48), withdrawal_credentials::binary-size(32), amount::integer-64-little,
      signature::binary-size(96)>> = bin

    struct!(
      SszTypes.DepositData,
      %{
        pubkey: pubkey,
        withdrawal_credentials: withdrawal_credentials,
        amount: amount,
        signature: signature
      }
    )
  end

  def decode_elixir(bin, schema) do
    schema_def = schema.schema()

    {_rest, items, _, _} =
      schema_def
      |> Enum.reduce({bin, %{}, [], 0}, fn s, {rest_bytes, items, offsets, index} ->
        key = Enum.at(Map.keys(s), 0)
        metadata = Map.get(s, key)

        case metadata do
          %{type: :list, schema: elements_schema, is_variable: false, max_size: max_size} ->
            %{size: element_size} = elements_schema
            <<elements::binary-size(max_size * element_size), rest::bitstring>> = rest_bytes

            decoded_list =
              :binary.bin_to_list(elements)
              |> Enum.chunk_every(element_size)
              |> Enum.map(fn c -> :binary.list_to_bin(c) end)

            {rest, Map.merge(items, %{key => decoded_list}), offsets, max_size * element_size}

          %{type: :struct, schema_struct: schema_struct} ->
            {rest_bytes, Map.merge(items, %{key => decode_elixir(rest_bytes, schema_struct)}),
             offsets, index}

            # unknown_schema -> {:error, "Unknown schema: #{inspect(schema)}"}
        end
      end)

    struct!(schema, items)
  end

  ##### HELPERS ##########
  defp is_variable_schema(map) when is_list(map) and map == [], do: true

  defp is_variable_schema(map) when is_list(map) do
    map
    |> Enum.map(fn schema ->
      key = Enum.at(Map.keys(schema), 0)
      metadata = Map.get(schema, key)
      is_variable_size(metadata)
    end)
    |> Enum.all?()
  end

  defp ssz_fixed_len(map) when is_list(map) do
    map
    |> Enum.map(fn schema ->
      key = Enum.at(Map.keys(schema), 0)
      metadata = Map.get(schema, key)
      byte_size_from_type(metadata)
    end)
    |> Enum.sum()
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

  defp is_variable_size(%{type: :struct, schema: schema}) do
    schema
    |> Enum.map(fn schema ->
      key = Enum.at(Map.keys(schema), 0)
      metadata = Map.get(schema, key)
      is_variable_size(metadata)
    end)
    |> Enum.all?()
  end

  defp is_variable_size(%{type: :list, is_variable: is_variable}), do: is_variable
  defp is_variable_size(%{type: :bytes}), do: false
  defp is_variable_size(%{type: :uint}), do: false
  defp is_variable_size(value) when is_binary(value), do: true

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
