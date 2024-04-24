defmodule SszEx.Merkleization do
  @moduledoc """
  The `Merkleization` module provides functions for computing Merkle roots of the SszEx schemas according to the Ethereum Simple Serialize (SSZ) specifications.
  """

  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Utils.BitVector
  alias SszEx.Encode
  alias SszEx.Error
  alias SszEx.Hash
  alias SszEx.Utils

  import Bitwise

  @bytes_per_chunk 32
  @bits_per_byte 8
  @bits_per_chunk @bytes_per_chunk * @bits_per_byte
  @zero_chunk <<0::size(@bits_per_chunk)>>
  @zero_hashes Hash.compute_zero_hashes()

  @spec hash_tree_root!(any, any) :: Types.root()
  def hash_tree_root!(value, schema) do
    {:ok, root} = hash_tree_root(value, schema)
    root
  end

  @spec hash_tree_root(boolean, atom) :: {:ok, Types.root()}
  def hash_tree_root(value, :bool), do: {:ok, pack(value, :bool)}

  @spec hash_tree_root(non_neg_integer, {:int, non_neg_integer}) :: {:ok, Types.root()}
  def hash_tree_root(value, {:int, size}), do: {:ok, pack(value, {:int, size})}

  @spec hash_tree_root(binary, {:byte_list, non_neg_integer}) :: {:ok, Types.root()}
  def hash_tree_root(value, {:byte_list, _size} = schema) do
    chunks = value |> pack_bytes()
    limit = chunk_count(schema)
    hash_tree_root_list(chunks, limit, value |> byte_size())
  end

  @spec hash_tree_root(binary, {:byte_vector, non_neg_integer}) ::
          {:ok, Types.root()}
  def hash_tree_root(value, {:byte_vector, size}) when byte_size(value) != size,
    do:
      {:error,
       %Error{
         message:
           "Invalid binary length while merkleizing byte_vector.\nExpected size: #{size}.\nFound: #{byte_size(value)}"
       }}

  def hash_tree_root(value, {:byte_vector, _size}) do
    packed_chunks = pack_bytes(value)
    leaf_count = packed_chunks |> get_chunks_len() |> next_pow_of_two()
    root = merkleize_chunks_with_virtual_padding(packed_chunks, leaf_count)
    {:ok, root}
  end

  @spec hash_tree_root(binary, {:bitlist | :bitvector, non_neg_integer}) :: {:ok, Types.root()}
  def hash_tree_root(value, {type, _size} = schema) when type in [:bitlist, :bitvector] do
    chunks = value |> pack_bits(type)
    leaf_count = chunk_count(schema) |> next_pow_of_two()
    root = chunks |> merkleize_chunks_with_virtual_padding(leaf_count)

    root =
      if type == :bitlist do
        len = value |> bit_size()
        root |> mix_in_length(len)
      else
        root
      end

    {:ok, root}
  end

  @spec hash_tree_root(list(), {:list, any, non_neg_integer}) ::
          {:ok, Types.root()} | {:error, Error.t()}
  def hash_tree_root(list, {:list, type, max_size} = schema) do
    len = Enum.count(list)

    cond do
      len > max_size ->
        {:error,
         %Error{
           message:
             "Invalid binary length while merkleizing list of #{inspect(type)}.\nExpected max_size: #{max_size}.\nFound: #{len}"
         }}

      Utils.basic_type?(type) ->
        list_hash_tree_root_basic(list, schema, len)

      true ->
        list_hash_tree_root_complex(list, schema, type, len)
    end
  end

  @spec hash_tree_root(list(), {:vector, any, non_neg_integer}) ::
          {:ok, Types.root()} | {:error, Error.t()}
  def hash_tree_root(vector, {:vector, inner_type, size}) when length(vector) != size,
    do:
      {:error,
       %Error{
         message:
           "Invalid binary length while merkleizing vector of #{inspect(inner_type)}.\nExpected size: #{size}.\nFound: #{length(vector)}"
       }}

  def hash_tree_root(vector, {:vector, type, _size} = schema) do
    value =
      if Utils.basic_type?(type) do
        pack(vector, schema)
      else
        list_hash_tree_root(vector, type)
      end

    case value do
      {:ok, chunks} -> chunks |> hash_tree_root_vector()
      {:error, %Error{}} -> value
      chunks -> chunks |> hash_tree_root_vector()
    end
  end

  @spec hash_tree_root(struct(), atom()) :: {:ok, Types.root()}
  def hash_tree_root(container, module) when is_map(container) do
    value =
      module.schema()
      |> Enum.reduce_while({:ok, <<>>}, fn {key, schema}, {_, acc_root} ->
        value = container |> Map.get(key)

        case hash_tree_root(value, schema) do
          {:ok, root} -> {:cont, {:ok, acc_root <> root}}
          {:error, %Error{} = error} -> {:halt, {:error, Error.add_trace(error, key)}}
        end
      end)

    case value do
      {:ok, chunks} ->
        leaf_count =
          chunks |> get_chunks_len() |> next_pow_of_two()

        root = chunks |> merkleize_chunks_with_virtual_padding(leaf_count)
        {:ok, root}

      {:error, %Error{}} ->
        value
    end
  end

  # TODO: make this work on any SSZ type and expose it in the API
  @spec compute_merkle_proof([Types.root()], non_neg_integer, non_neg_integer) :: [Types.root()]
  def compute_merkle_proof(leaves, index, height) do
    compute_merkle_proof(leaves, index, 0, height, [])
  end

  defp compute_merkle_proof([_root], _, max_height, max_height, proof) do
    Enum.reverse(proof)
  end

  defp compute_merkle_proof(leaves, index, height, max_height, proof) do
    default_value = get_zero_hash(height)

    sibling_index = index - rem(index, 2) * 2 + 1
    proof_element = Enum.at(leaves, sibling_index, default_value)

    Stream.chunk_every(leaves, 2)
    |> Enum.map(fn
      [left, right] -> Hash.hash_nodes(left, right)
      [node] -> Hash.hash_nodes(node, default_value)
    end)
    |> compute_merkle_proof(div(index, 2), height + 1, max_height, [proof_element | proof])
  end

  defp list_hash_tree_root_basic(list, schema, len) do
    limit = chunk_count(schema)
    pack(list, schema) |> hash_tree_root_list(limit, len)
  end

  defp list_hash_tree_root_complex(list, schema, type, len) do
    limit = chunk_count(schema)

    with {:ok, chunks} <- list_hash_tree_root(list, type),
         result <- hash_tree_root_list(chunks, limit, len) do
      result
    end
  end

  defp hash_tree_root_vector(chunks) do
    leaf_count = chunks |> get_chunks_len() |> next_pow_of_two()
    root = merkleize_chunks_with_virtual_padding(chunks, leaf_count)
    {:ok, root}
  end

  defp hash_tree_root_list(chunks, limit, len) do
    root = merkleize_chunks_with_virtual_padding(chunks, limit) |> mix_in_length(len)
    {:ok, root}
  end

  defp list_hash_tree_root(list, inner_schema) do
    list
    |> Enum.reduce_while({:ok, <<>>}, fn value, {_, acc_roots} ->
      case hash_tree_root(value, inner_schema) do
        {:ok, root} -> {:cont, {:ok, acc_roots <> root}}
        {:error, %Error{}} = error -> {:halt, error}
      end
    end)
  end

  @spec mix_in_length(Types.root(), non_neg_integer) :: Types.root()
  def mix_in_length(root, len) do
    {:ok, serialized_len} = Encode.encode(len, {:int, @bits_per_chunk})
    root |> Hash.hash_nodes(serialized_len)
  end

  # TODO: we are not using this
  def merkleize_chunks(chunks, leaf_count \\ nil) do
    chunks_len = chunks |> get_chunks_len()

    if chunks_len == 1 and leaf_count == nil do
      chunks
    else
      power = leaf_count |> compute_pow()
      height = power + 1
      first_layer = chunks |> convert_to_next_pow_of_two(leaf_count)

      final_layer =
        (height - 1)..1
        |> Enum.reduce(first_layer, fn _i, acc_layer ->
          get_parent_layer(acc_layer)
        end)

      final_layer
    end
  end

  def merkleize_chunks_with_virtual_padding(chunks, leaf_count) do
    chunks_len = chunks |> get_chunks_len()
    power = leaf_count |> compute_pow()
    height = power + 1

    cond do
      chunks_len == 0 ->
        depth = height - 1
        get_zero_hash(depth)

      chunks_len == 1 and leaf_count == 1 ->
        chunks

      true ->
        first_layer = chunks
        last_index = chunks_len - 1

        {_, final_layer} =
          1..(height - 1)
          |> Enum.reverse()
          |> Enum.reduce({last_index, first_layer}, fn i, {current_last_index, current_layer} ->
            parent_layers = get_parent_layer(i, height, current_layer, current_last_index)
            {current_last_index |> div(2), parent_layers}
          end)

        <<root::binary-size(@bytes_per_chunk), _::binary>> = final_layer
        root
    end
  end

  @spec get_zero_hash(non_neg_integer()) :: binary()
  def get_zero_hash(depth), do: Hash.get_zero_hash(depth, @zero_hashes)

  @spec pack(boolean, :bool) :: binary()
  def pack(true, :bool), do: <<1::@bits_per_chunk-little>>
  def pack(false, :bool), do: @zero_chunk

  @spec pack(non_neg_integer, {:int, non_neg_integer}) :: binary()
  def pack(value, {:int, size}) do
    <<value::size(size)-little>> |> pack_bytes()
  end

  @spec pack(list(), {:list | :vector, any, non_neg_integer}) :: binary() | {:error, Error.t()}
  def pack(list, {type, schema, _}) when type in [:vector, :list] do
    list
    |> Enum.reduce(<<>>, fn x, acc ->
      {:ok, encoded} = Encode.encode(x, schema)
      acc <> encoded
    end)
    |> pack_bytes()
  end

  defp pack_bits(value, :bitvector) do
    BitVector.to_bytes(value) |> pack_bytes()
  end

  defp pack_bits(value, :bitlist) do
    value |> BitList.to_packed_bytes() |> pack_bytes()
  end

  def chunk_count({:list, type, max_size}) do
    if Utils.basic_type?(type) do
      size = Utils.size_of(type)
      (max_size * size + 31) |> div(32)
    else
      max_size
    end
  end

  def chunk_count({:byte_list, max_size}), do: (max_size + 31) |> div(32)

  def chunk_count({identifier, size}) when identifier in [:bitlist, :bitvector] do
    (size + @bits_per_chunk - 1) |> div(@bits_per_chunk)
  end

  defp pack_bytes(value) when is_binary(value) do
    incomplete_chunk_len = value |> bit_size() |> rem(@bits_per_chunk)

    if incomplete_chunk_len != 0 do
      pad = @bits_per_chunk - incomplete_chunk_len
      <<value::binary, 0::size(pad)>>
    else
      value
    end
  end

  defp convert_to_next_pow_of_two(chunks, leaf_count) do
    size = chunks |> byte_size() |> div(@bytes_per_chunk)
    next_pow = leaf_count |> next_pow_of_two()

    if size == next_pow do
      chunks
    else
      diff = next_pow - size
      zero_chunks = 0..(diff - 1) |> Enum.reduce(<<>>, fn _, acc -> <<0::256>> <> acc end)
      chunks <> zero_chunks
    end
  end

  defp next_pow_of_two(0), do: 0

  defp next_pow_of_two(len) when is_integer(len) and len > 0 do
    n = ((len <<< 1) - 1) |> compute_pow()
    2 ** n
  end

  defp get_chunks_len(chunks) do
    chunks |> byte_size() |> div(@bytes_per_chunk)
  end

  defp compute_pow(value) do
    :math.log2(value) |> trunc()
  end

  defp get_parent_layer(i, height, current_layer, current_last_index) do
    0..current_last_index
    |> Enum.filter(fn x -> rem(x, 2) == 0 end)
    |> Enum.reduce(<<>>, fn j, acc_parent_layer ->
      {left, right} = get_nodes(i, j, height, current_layer, current_last_index)
      acc_parent_layer <> Hash.hash_nodes(left, right)
    end)
  end

  defp get_parent_layer(current_layer) do
    0..(get_chunks_len(current_layer) - 1)
    |> Enum.filter(fn x -> rem(x, 2) == 0 end)
    |> Enum.reduce(<<>>, fn j, acc_parent_layer ->
      {left, right} = get_nodes(j, current_layer)
      acc_parent_layer <> Hash.hash_nodes(left, right)
    end)
  end

  defp get_nodes(left_children_index, current_layer) do
    children = extract_chunks(left_children_index, current_layer, 2)

    <<left::binary-size(@bytes_per_chunk), right::binary-size(@bytes_per_chunk)>> =
      children

    {left, right}
  end

  defp get_nodes(_i, left_children_index, _height, current_layer, current_last_index)
       when left_children_index < current_last_index do
    get_nodes(left_children_index, current_layer)
  end

  defp get_nodes(i, left_children_index, height, current_layer, current_last_index)
       when left_children_index == current_last_index do
    left = extract_chunks(left_children_index, current_layer, 1)
    depth = height - i - 1
    right = get_zero_hash(depth)
    {left, right}
  end

  def extract_chunks(left_chunk_index, chunks, chunk_count) do
    start = left_chunk_index * @bytes_per_chunk
    stop = (left_chunk_index + chunk_count) * @bytes_per_chunk
    extracted_chunks = chunks |> :binary.part(start, stop - start)
    extracted_chunks
  end
end
