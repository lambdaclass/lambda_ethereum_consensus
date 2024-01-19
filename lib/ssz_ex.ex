defmodule LambdaEthereumConsensus.SszEx do
  @moduledoc """
    SSZ library in Elixir
  """
  alias LambdaEthereumConsensus.Utils.BitVector
  import alias LambdaEthereumConsensus.Utils.BitVector

  #################
  ### Public API
  #################
  import Bitwise

  @bytes_per_chunk 32
  @bits_per_byte 8
  @bits_per_chunk @bytes_per_chunk * @bits_per_byte
  @zero_chunk <<0::size(@bits_per_chunk)>>
  @zero_hashes <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                 0, 0, 0, 0, 0, 245, 165, 253, 66, 209, 106, 32, 48, 39, 152, 239, 110, 211, 9,
                 151, 155, 67, 0, 61, 35, 32, 217, 240, 232, 234, 152, 49, 169, 39, 89, 251, 75,
                 219, 86, 17, 78, 0, 253, 212, 193, 248, 92, 137, 43, 243, 90, 201, 168, 146, 137,
                 170, 236, 177, 235, 208, 169, 108, 222, 96, 106, 116, 139, 93, 113, 199, 128, 9,
                 253, 240, 127, 197, 106, 17, 241, 34, 55, 6, 88, 163, 83, 170, 165, 66, 237, 99,
                 228, 76, 75, 193, 95, 244, 205, 16, 90, 179, 60, 83, 109, 152, 131, 127, 45, 209,
                 101, 165, 93, 94, 234, 233, 20, 133, 149, 68, 114, 213, 111, 36, 109, 242, 86,
                 191, 60, 174, 25, 53, 42, 18, 60, 158, 253, 224, 82, 170, 21, 66, 159, 174, 5,
                 186, 212, 208, 177, 215, 198, 77, 166, 77, 3, 215, 161, 133, 74, 88, 140, 44,
                 184, 67, 12, 13, 48, 216, 141, 223, 238, 212, 0, 168, 117, 85, 150, 178, 25, 66,
                 193, 73, 126, 17, 76, 48, 46, 97, 24, 41, 15, 145, 230, 119, 41, 118, 4, 31, 161,
                 135, 235, 13, 219, 165, 126, 53, 246, 210, 134, 103, 56, 2, 164, 175, 89, 117,
                 226, 37, 6, 199, 207, 76, 100, 187, 107, 229, 238, 17, 82, 127, 44, 38, 132, 100,
                 118, 253, 95, 197, 74, 93, 67, 56, 81, 103, 201, 81, 68, 242, 100, 63, 83, 60,
                 200, 91, 185, 209, 107, 120, 47, 141, 125, 177, 147, 80, 109, 134, 88, 45, 37,
                 36, 5, 184, 64, 1, 135, 146, 202, 210, 191, 18, 89, 241, 239, 90, 165, 248, 135,
                 225, 60, 178, 240, 9, 79, 81, 225, 255, 255, 10, 215, 230, 89, 119, 47, 149, 52,
                 193, 149, 200, 21, 239, 196, 1, 78, 241, 225, 218, 237, 68, 4, 192, 99, 133, 209,
                 17, 146, 233, 43, 108, 240, 65, 39, 219, 5, 68, 28, 216, 51, 16, 122, 82, 190,
                 133, 40, 104, 137, 14, 67, 23, 230, 160, 42, 180, 118, 131, 170, 117, 150, 66,
                 32, 183, 208, 95, 135, 95, 20, 0, 39, 239, 81, 24, 162, 36, 123, 187, 132, 206,
                 143, 47, 15, 17, 35, 98, 48, 133, 218, 247, 150, 12, 50, 159, 95, 223, 106, 245,
                 245, 187, 219, 107, 233, 239, 138, 166, 24, 228, 191, 128, 115, 150, 8, 103, 23,
                 30, 41, 103, 111, 139, 40, 77, 234, 106, 8, 168, 94, 181, 141, 144, 15, 94, 24,
                 46, 60, 80, 239, 116, 150, 158, 161, 108, 119, 38, 197, 73, 117, 124, 194, 53,
                 35, 195, 105, 88, 125, 167, 41, 55, 132, 212, 154, 117, 2, 255, 207, 176, 52, 11,
                 29, 120, 133, 104, 133, 0, 202, 48, 129, 97, 167, 249, 107, 98, 223, 157, 8, 59,
                 113, 252, 200, 242, 187, 143, 230, 177, 104, 146, 86, 192, 211, 133, 244, 47, 91,
                 190, 32, 39, 162, 44, 25, 150, 225, 16, 186, 151, 193, 113, 211, 229, 148, 141,
                 233, 43, 235, 141, 13, 99, 195, 158, 186, 222, 133, 9, 224, 174, 60, 156, 56,
                 118, 251, 95, 161, 18, 190, 24, 249, 5, 236, 172, 254, 203, 146, 5, 118, 3, 171,
                 149, 238, 200, 178, 229, 65, 202, 212, 233, 29, 227, 131, 133, 242, 224, 70, 97,
                 159, 84, 73, 108, 35, 130, 203, 108, 172, 213, 185, 140, 38, 245, 164, 248, 147,
                 233, 8, 145, 119, 117, 182, 43, 255, 35, 41, 77, 187, 227, 161, 205, 142, 108,
                 193, 195, 91, 72, 1, 136, 123, 100, 106, 111, 129, 241, 127, 205, 219, 167, 181,
                 146, 227, 19, 51, 147, 193, 97, 148, 250, 199, 67, 26, 191, 47, 84, 133, 237,
                 113, 29, 178, 130, 24, 60, 129, 158, 8, 235, 170, 138, 141, 127, 227, 175, 140,
                 170, 8, 90, 118, 57, 168, 50, 0, 20, 87, 223, 185, 18, 138, 128, 97, 20, 42, 208,
                 51, 86, 41, 255, 35, 255, 156, 254, 179, 195, 55, 215, 165, 26, 111, 191, 0, 185,
                 227, 76, 82, 225, 201, 25, 92, 150, 155, 212, 231, 160, 191, 213, 29, 92, 91,
                 237, 156, 17, 103, 231, 31, 10, 168, 60, 195, 46, 223, 190, 250, 159, 77, 62, 1,
                 116, 202, 133, 24, 46, 236, 159, 58, 9, 246, 166, 192, 223, 99, 119, 165, 16,
                 215, 49, 32, 111, 168, 10, 80, 187, 106, 190, 41, 8, 80, 88, 241, 98, 18, 33, 42,
                 96, 238, 200, 240, 73, 254, 203, 146, 216, 200, 224, 168, 75, 192, 33, 53, 43,
                 254, 203, 237, 221, 233, 147, 131, 159, 97, 76, 61, 172, 10, 62, 227, 117, 67,
                 249, 180, 18, 177, 97, 153, 220, 21, 142, 35, 181, 68, 97, 158, 49, 39, 36, 187,
                 109, 124, 49, 83, 237, 157, 231, 145, 215, 100, 163, 102, 179, 137, 175, 19, 197,
                 139, 248, 168, 217, 4, 129, 164, 103, 101, 124, 221, 41, 134, 38, 130, 80, 98,
                 141, 12, 16, 227, 133, 197, 140, 97, 145, 230, 251, 224, 81, 145, 188, 192, 79,
                 19, 63, 44, 234, 114, 193, 196, 132, 137, 48, 189, 123, 168, 202, 197, 70, 97, 7,
                 33, 19, 251, 39, 136, 105, 224, 123, 184, 88, 127, 145, 57, 41, 51, 55, 77, 1,
                 123, 203, 225, 136, 105, 255, 44, 34, 178, 140, 193, 5, 16, 217, 133, 50, 146,
                 128, 51, 40, 190, 79, 176, 232, 4, 149, 232, 187, 141, 39, 31, 91, 136, 150, 54,
                 181, 254, 40, 231, 159, 27, 133, 15, 134, 88, 36, 108, 233, 182, 161, 231, 180,
                 159, 192, 109, 183, 20, 62, 143, 224, 180, 242, 176, 197, 82, 58, 92, 152, 94,
                 146, 159, 112, 175, 40, 208, 189, 209, 169, 10, 128, 143, 151, 127, 89, 124, 124,
                 119, 140, 72, 158, 152, 211, 189, 137, 16, 211, 26, 192, 247, 198, 246, 126, 2,
                 230, 228, 225, 189, 239, 185, 148, 198, 9, 137, 83, 243, 70, 54, 186, 43, 108,
                 162, 10, 71, 33, 210, 178, 106, 136, 103, 34, 255, 28, 154, 126, 95, 241, 207,
                 72, 180, 173, 21, 130, 211, 244, 228, 161, 0, 79, 59, 32, 216, 197, 162, 183, 19,
                 135, 164, 37, 74, 217, 51, 235, 197, 47, 7, 90, 226, 41, 100, 107, 111, 106, 237,
                 25, 165, 227, 114, 207, 41, 80, 129, 64, 30, 184, 147, 255, 89, 155, 63, 154,
                 204, 12, 13, 62, 125, 50, 137, 33, 222, 181, 150, 18, 7, 104, 1, 232, 205, 97,
                 89, 33, 7, 181, 198, 124, 121, 184, 70, 89, 92, 198, 50, 12, 57, 91, 70, 54, 44,
                 191, 185, 9, 253, 178, 54, 173, 36, 17, 180, 228, 136, 56, 16, 160, 116, 184, 64,
                 70, 70, 137, 152, 108, 63, 138, 128, 145, 130, 126, 23, 195, 39, 85, 216, 251,
                 54, 135, 186, 59, 164, 159, 52, 44, 119, 245, 161, 248, 155, 236, 131, 216, 17,
                 68, 110, 26, 70, 113, 57, 33, 61, 100, 11, 106, 116, 247, 33, 13, 79, 142, 126,
                 16, 57, 121, 14, 123, 244, 239, 162, 7, 85, 90, 16, 166, 219, 29, 212, 185, 93,
                 163, 19, 170, 168, 139, 136, 254, 118, 173, 33, 181, 22, 203, 198, 69, 255, 227,
                 74, 181, 222, 28, 138, 239, 140, 212, 231, 248, 210, 181, 30, 142, 20, 86, 173,
                 199, 86, 60, 218, 32, 111, 107, 254, 141, 43, 204, 66, 55, 183, 74, 80, 71, 5,
                 142, 244, 85, 51, 158, 205, 115, 96, 203, 99, 191, 187, 142, 229, 68, 142, 100,
                 48, 186, 4, 167, 242, 60, 233, 24, 23, 64, 220, 34, 12, 129, 71, 130, 101, 79,
                 238, 106, 206, 185, 241, 236, 146, 34, 196, 226, 70, 125, 10, 177, 104, 8, 55,
                 174, 249, 71, 108, 137, 89, 10, 44, 140, 201, 179, 183, 79, 73, 103, 199, 87,
                 196, 157, 152, 102, 164, 75, 172, 242, 31, 162, 237, 103, 93, 223, 162, 154, 66,
                 188, 173, 130, 246, 169, 228, 18, 132, 216, 8, 234, 211, 25, 242, 159, 59, 8, 32,
                 157, 104, 15, 14, 44, 231, 21, 16, 208, 113, 226, 5, 209, 166, 109, 53, 74, 103,
                 185, 207, 23, 149, 113, 216, 229, 249, 119, 146, 113, 110, 141, 212, 236, 68, 25,
                 104, 57, 163, 247, 198, 183, 79, 139, 172, 250, 250, 48, 37, 242, 248, 149, 9,
                 194, 199, 28, 116, 251, 160, 205, 146, 133, 142, 244, 155, 7, 128, 251, 84, 121,
                 116, 108, 138, 155, 252, 179, 70, 51, 52, 167, 193, 231, 246, 112, 90, 166, 1,
                 26, 106, 148, 150, 69, 1, 109, 180, 172, 222, 12, 169, 171, 214, 109, 199, 157,
                 130, 102, 66, 48, 86, 7, 150, 253, 117, 102, 79, 174, 247, 68, 238, 78, 82, 215,
                 39, 30, 43, 187, 118, 159, 145, 237, 111, 155, 116, 216, 182, 148, 245, 102, 6,
                 133, 44, 123, 163, 174, 74, 65, 127, 232, 84, 91, 20, 43, 200, 159, 74, 220, 215,
                 174, 19, 148, 28, 186, 183, 117, 11, 131, 233, 240, 166, 109, 22, 190, 100, 120,
                 143, 175, 204, 74, 165, 32, 57, 154, 219, 174, 209, 149, 248, 177, 44, 78, 179,
                 30, 193, 1, 104, 229, 10, 171, 198, 89, 166, 174, 165, 22, 220, 232, 51, 215,
                 166, 113, 96, 230, 139, 244, 201, 4, 74, 83, 7, 125, 242, 114, 122, 208, 12, 243,
                 111, 73, 73, 199, 182, 129, 169, 18, 20, 12, 187, 48, 158, 171, 240, 149, 220,
                 103, 20, 249, 244, 216, 100, 187, 165, 175, 250, 224, 179, 90, 226, 245, 227, 86,
                 91, 204, 58, 71, 178, 18, 118, 119, 1, 34, 106, 142, 190, 250, 40, 134, 101, 166,
                 68, 165, 2, 115, 51, 94, 251, 182, 16, 81, 15, 36, 27, 91, 114, 12, 138, 54, 141,
                 89, 166, 154, 93, 65, 171, 253, 153, 84, 37, 130, 118, 37, 147, 129, 49, 175, 12,
                 79, 51, 254, 11, 212, 104, 140, 34, 44, 33, 250, 157, 168, 232, 156, 170, 3, 248,
                 68, 44, 100, 46, 245, 15, 161, 166, 103, 166, 230, 209, 5, 199, 124, 92, 195,
                 254, 200, 215, 170, 37, 112, 207, 26, 48, 119, 181, 3, 195, 128, 105, 160, 160,
                 141, 252, 155, 66, 217, 108, 45, 225, 155, 109, 18, 123, 138, 225, 54, 221, 207,
                 62, 90, 208, 220, 228, 34, 196, 90, 86, 246, 31, 106, 116, 125, 52, 131, 130,
                 175, 9, 109, 190, 11, 240, 134, 199, 187, 57, 178, 162, 192, 188, 54, 182, 33,
                 171, 12, 115, 142, 152, 133, 215, 49, 216, 23, 64, 58, 177, 52, 117, 29, 25, 18,
                 105, 2, 108, 134, 153, 78, 170, 139, 67, 168, 59, 74, 209, 246, 208, 231, 115,
                 129, 196, 226, 151, 74, 251, 200, 246, 154, 116, 82, 97, 29, 178, 210, 62, 174,
                 38, 249, 189, 187, 136, 149, 142, 244, 76, 100, 208, 254, 152, 123, 233, 247, 38,
                 173, 249, 56, 245, 15, 108, 114, 92, 127, 129, 96, 55, 191, 228, 82, 205, 30,
                 123, 163, 90, 196, 126, 220, 180, 154, 154, 43, 39, 174, 202, 112, 220, 228, 131,
                 203, 125, 237, 31, 44, 234, 26, 245, 31, 178, 139, 98, 136, 124, 57, 153, 138,
                 201, 254, 244, 223, 222, 218, 31, 7, 224, 113, 186, 85, 138, 23, 58, 253, 6, 203,
                 195, 255, 29, 89, 249, 139, 108, 85, 29, 149, 8, 147, 87, 5, 125, 92, 139, 226,
                 100, 2, 39, 158, 157, 240, 177, 223, 26, 16, 183, 43, 243, 146, 127, 47, 138, 24,
                 31, 124, 153, 221, 33, 90, 117, 41, 191, 226, 150, 169, 96, 58, 20, 70, 115, 113,
                 134, 210, 26, 235, 139, 199, 174, 89, 225, 253, 33, 236, 197, 2, 201, 177, 20,
                 95, 57, 80, 203, 125, 62, 56, 66, 68, 111, 129, 164, 240, 223, 29, 245, 55, 206,
                 225, 57, 239, 100, 234, 152, 75, 217>>

  @spec hash(iodata()) :: binary()
  def hash(data), do: :crypto.hash(:sha256, data)

  @spec hash_nodes(binary(), binary()) :: binary()
  def hash_nodes(left, right), do: :crypto.hash(:sha256, left <> right)

  def encode(value, {:int, size}), do: encode_int(value, size)
  def encode(value, :bool), do: encode_bool(value)
  def encode(value, {:bytes, _}), do: {:ok, value}

  def encode(list, {:list, basic_type, size}) do
    if variable_size?(basic_type),
      do: encode_variable_size_list(list, basic_type, size),
      else: encode_fixed_size_list(list, basic_type, size)
  end

  def encode(vector, {:vector, basic_type, size}),
    do: encode_fixed_size_list(vector, basic_type, size)

  def encode(value, {:bitlist, max_size}) when is_bitstring(value),
    do: encode_bitlist(value, max_size)

  def encode(value, {:bitlist, max_size}) when is_integer(value),
    do: encode_bitlist(:binary.encode_unsigned(value), max_size)

  def encode(value, {:bitvector, size}) when is_bitvector(value),
    do: encode_bitvector(value, size)

  def encode(container, module) when is_map(container),
    do: encode_container(container, module.schema())

  def decode(binary, :bool), do: decode_bool(binary)
  def decode(binary, {:int, size}), do: decode_uint(binary, size)
  def decode(value, {:bytes, _}), do: {:ok, value}

  def decode(binary, {:list, basic_type, size}) do
    if variable_size?(basic_type),
      do: decode_variable_list(binary, basic_type, size),
      else: decode_list(binary, basic_type, size)
  end

  def decode(binary, {:vector, basic_type, size}), do: decode_list(binary, basic_type, size)

  def decode(value, {:bitlist, max_size}) when is_bitstring(value),
    do: decode_bitlist(value, max_size)

  def decode(value, {:bitvector, size}) when is_bitstring(value),
    do: decode_bitvector(value, size)

  def decode(binary, module) when is_atom(module), do: decode_container(binary, module)

  @spec hash_tree_root!(boolean, atom) :: Types.root()
  def hash_tree_root!(value, :bool), do: pack(value, :bool)

  @spec hash_tree_root!(non_neg_integer, {:int, non_neg_integer}) :: Types.root()
  def hash_tree_root!(value, {:int, size}), do: pack(value, {:int, size})

  @spec hash_tree_root(list(), {:list, any, non_neg_integer}) ::
          {:ok, Types.root()} | {:error, String.t()}
  def hash_tree_root(list, {:list, type, size}) do
    if variable_size?(type) do
      # TODO
      # hash_tree_root_list_complex_type(list, {:list, type, size}, limit)
      {:error, "Not implemented"}
    else
      packed_chunks = pack(list, {:list, type, size})
      limit = chunk_count({:list, type, size})
      len = length(list)
      hash_tree_root_list_basic_type(packed_chunks, limit, len)
    end
  end

  @spec hash_tree_root(list(), {:vector, any, non_neg_integer}) ::
          {:ok, Types.root()} | {:error, String.t()}
  def hash_tree_root(vector, {:vector, type, size}) do
    if variable_size?(type) do
      # TODO
      # hash_tree_root_vector_complex_type(vector, {:vector, type, size}, limit)
      {:error, "Not implemented"}
    else
      packed_chunks = pack(vector, {:list, type, size})
      hash_tree_root_vector_basic_type(packed_chunks)
    end
  end

  @spec hash_tree_root_list_basic_type(binary(), non_neg_integer, non_neg_integer) ::
          {:ok, Types.root()} | {:error, String.t()}
  def hash_tree_root_list_basic_type(chunks, limit, len) do
    chunks_len = chunks |> get_chunks_len()

    if chunks_len > limit do
      {:error, "chunk size exceeds limit"}
    else
      root = merkleize_chunks(chunks, limit) |> mix_in_length(len)
      {:ok, root}
    end
  end

  @spec hash_tree_root_vector_basic_type(binary()) ::
          {:ok, Types.root()} | {:error, String.t()}
  def hash_tree_root_vector_basic_type(chunks) do
    leaf_count = chunks |> get_chunks_len() |> next_pow_of_two()
    root = merkleize_chunks(chunks, leaf_count)
    {:ok, root}
  end

  @spec mix_in_length(Types.root(), non_neg_integer) :: Types.root()
  def mix_in_length(root, len) do
    {:ok, serialized_len} = encode_int(len, @bits_per_chunk)
    root |> hash_nodes(serialized_len)
  end

  def merkleize_chunks(chunks, leaf_count \\ nil) do
    chunks_len = chunks |> get_chunks_len()

    if chunks_len == 1 and leaf_count == nil do
      chunks
    else
      node_count = 2 * leaf_count - 1
      interior_count = node_count - leaf_count
      leaf_start = interior_count * @bytes_per_chunk
      padded_chunks = chunks |> convert_to_next_pow_of_two(leaf_count)
      buffer = <<0::size(leaf_start * @bits_per_byte), padded_chunks::bitstring>>

      new_buffer =
        1..node_count
        |> Enum.filter(fn x -> rem(x, 2) == 0 end)
        |> Enum.reverse()
        |> Enum.reduce(buffer, fn index, acc_buffer ->
          parent_index = (index - 1) |> div(2)
          start = parent_index * @bytes_per_chunk
          stop = (index + 1) * @bytes_per_chunk
          focus = acc_buffer |> :binary.part(start, stop - start)
          focus_len = focus |> byte_size()
          children_index = focus_len - 2 * @bytes_per_chunk
          children = focus |> :binary.part(children_index, focus_len - children_index)

          <<left::binary-size(@bytes_per_chunk), right::binary-size(@bytes_per_chunk)>> = children

          parent = hash_nodes(left, right)
          replace_chunk(acc_buffer, start, parent)
        end)

      <<root::binary-size(@bytes_per_chunk), _::binary>> = new_buffer
      root
    end
  end

  def merkleize_chunks_with_virtual_padding(chunks, leaf_count \\ nil) do
    chunks_count = chunks |> get_chunks_len()

    if chunks_count == 0 and leaf_count == nil do
      @zero_chunk
    else
      power = leaf_count |> compute_pow()
      height = power + 1
      layers = chunks
      last_index = chunks_count - 1

      1..(height - 1)
      |> Enum.reverse()
      |> Enum.reduce(last_index, fn i, acc_last_index ->
        0..(2 ** i - 1)
        |> Enum.filter(fn x -> rem(x, 2) == 0 end)
        |> Enum.reduce_while(layers, fn j, acc_layers ->
          parent_index = j |> div(2)

          nodes =
            cond do
              j < acc_last_index ->
                start = parent_index * @bytes_per_chunk
                stop = (j + 2) * @bytes_per_chunk
                focus = acc_layers |> :binary.part(start, stop - start)
                focus_len = focus |> byte_size()
                children_index = focus_len - 2 * @bytes_per_chunk
                <<parent::binary-size(children_index), children::binary>> = focus

                <<left::binary-size(@bytes_per_chunk), right::binary-size(@bytes_per_chunk)>> =
                  children

                {parent, left, right}

              j == acc_last_index ->
                start = parent_index * @bytes_per_chunk
                stop = (j + 1) * @bytes_per_chunk
                focus = acc_layers |> :binary.part(start, stop - start)
                focus_len = focus |> byte_size()
                children_index = focus_len - @bytes_per_chunk
                <<parent::binary-size(children_index), left::binary>> = focus
                depth = height - i - 1

                right = @zero_hashes |> :binary.part(depth - 1, @bytes_per_chunk)
                {parent, left, right}

              true ->
                :error
            end

          case nodes do
            :error ->
              {:halt, acc_layers}

            {parent, left, right} ->
              if j == 0 do
                hash = hash_nodes(left, right)
                acc_layers |> IO.inspect()
                {:cont, acc_layers}
              else
                parent = hash_nodes(left, right)
                acc_layers |> IO.inspect()
                {:cont, acc_layers}
              end
          end
        end)

        acc_last_index |> div(2)
      end)
    end
  end

  @spec pack(boolean, :bool) :: binary()
  def pack(true, :bool), do: <<1::@bits_per_chunk-little>>
  def pack(false, :bool), do: @zero_chunk

  @spec pack(non_neg_integer, {:int, non_neg_integer}) :: binary()
  def pack(value, {:int, size}) do
    <<value::size(size)-little>> |> pack_bytes()
  end

  @spec pack(list(), {:list | :vector, any, non_neg_integer}) :: binary() | :error
  def pack(list, {type, schema, _}) when type in [:vector, :list] do
    if variable_size?(schema) do
      # TODO
      # pack_complex_type_list(list)
      :error
    else
      pack_basic_type_list(list, schema)
    end
  end

  def chunk_count({:list, {:int, size}, max_size}) do
    size = size_of({:int, size})
    (max_size * size + 31) |> div(32)
  end

  def chunk_count({:list, :bool, max_size}) do
    size = size_of(:bool)
    (max_size * size + 31) |> div(32)
  end

  #################
  ### Private functions
  #################
  @bytes_per_boolean 4
  @bytes_per_length_offset 4
  @offset_bits 32

  defp encode_int(value, size) when is_integer(value), do: {:ok, <<value::size(size)-little>>}
  defp encode_bool(true), do: {:ok, "\x01"}
  defp encode_bool(false), do: {:ok, "\x00"}

  defp decode_uint(binary, size) do
    <<element::integer-size(size)-little, _rest::bitstring>> = binary
    {:ok, element}
  end

  defp decode_bool("\x01"), do: {:ok, true}
  defp decode_bool("\x00"), do: {:ok, false}

  defp encode_fixed_size_list(list, _basic_type, max_size) when length(list) > max_size,
    do: {:error, "invalid max_size of list"}

  defp encode_fixed_size_list(list, basic_type, _size) when is_list(list) do
    list
    |> Enum.map(&encode(&1, basic_type))
    |> flatten_results_by(&Enum.join/1)
  end

  defp encode_bitlist(bit_list, max_size) do
    len = bit_size(bit_list)

    if len > max_size do
      {:error, "excess bits"}
    else
      r = rem(len, @bits_per_byte)
      <<pre::bitstring-size(len - r), post::bitstring-size(r)>> = bit_list
      {:ok, <<pre::bitstring, 1::size(@bits_per_byte - r), post::bitstring>>}
    end
  end

  defp encode_bitvector(bit_vector, size) when bit_vector_size(bit_vector) == size,
    do: {:ok, BitVector.to_bytes(bit_vector)}

  defp encode_bitvector(_bit_vector, _size), do: {:error, "invalid bit_vector length"}

  defp encode_variable_size_list(list, _basic_type, max_size) when length(list) > max_size,
    do: {:error, "invalid max_size of list"}

  defp encode_variable_size_list(list, basic_type, _size) when is_list(list) do
    fixed_lengths = @bytes_per_length_offset * length(list)

    with {:ok, {encoded_variable_parts, variable_offsets_list, total_byte_size}} <-
           encode_variable_parts(list, basic_type),
         :ok <- check_length(fixed_lengths, total_byte_size),
         {variable_offsets, _} =
           Enum.reduce(variable_offsets_list, {[], 0}, fn element, {res, acc} ->
             sum = fixed_lengths + acc
             {[sum | res], element + acc}
           end),
         {:ok, encoded_variable_offsets} <-
           variable_offsets
           |> Enum.reverse()
           |> Enum.map(&encode(&1, {:int, 32}))
           |> flatten_results() do
      (encoded_variable_offsets ++ encoded_variable_parts)
      |> :binary.list_to_bin()
      |> then(&{:ok, &1})
    end
  end

  defp encode_variable_parts(list, basic_type) do
    with {:ok, {encoded_list, byte_size_list, total_byte_size}} <-
           Enum.reduce_while(list, {:ok, {[], [], 0}}, fn value,
                                                          {:ok, {res_encoded, res_size, acc}} ->
             case encode(value, basic_type) do
               {:ok, encoded} ->
                 size = byte_size(encoded)
                 {:cont, {:ok, {[encoded | res_encoded], [size | res_size], size + acc}}}

               error ->
                 {:halt, {:error, error}}
             end
           end) do
      {:ok, {Enum.reverse(encoded_list), Enum.reverse(byte_size_list), total_byte_size}}
    end
  end

  defp decode_bitlist(bit_list, max_size) do
    num_bytes = byte_size(bit_list)
    num_bits = bit_size(bit_list)
    len = length_of_bitlist(bit_list)
    <<pre::size(num_bits - 8), last_byte::8>> = bit_list
    decoded = <<pre::size(num_bits - 8), remove_trailing_bit(<<last_byte>>)::bitstring>>

    cond do
      len < 0 ->
        {:error, "missing length information"}

      div(len, @bits_per_byte) + 1 != num_bytes ->
        {:error, "invalid byte count"}

      len > max_size ->
        {:error, "out of bounds"}

      true ->
        {:ok, decoded}
    end
  end

  defp decode_bitvector(bit_vector, size) when bit_size(bit_vector) == size,
    do: {:ok, BitVector.new(bit_vector, size)}

  defp decode_bitvector(_bit_vector, _size), do: {:error, "invalid bit_vector length"}

  defp decode_list(binary, basic_type, size) do
    fixed_size = get_fixed_size(basic_type)

    with {:ok, decoded_list} = result <-
           binary
           |> decode_chunk(fixed_size, basic_type)
           |> flatten_results() do
      if length(decoded_list) > size do
        {:error, "invalid max_size of list"}
      else
        result
      end
    end
  end

  defp decode_variable_list(binary, _, _) when byte_size(binary) == 0 do
    {:ok, []}
  end

  defp decode_variable_list(
         <<first_offset::integer-32-little, _rest_bytes::bitstring>>,
         _basic_type,
         size
       )
       when div(first_offset, @bytes_per_length_offset) > size,
       do: {:error, "invalid length list"}

  defp decode_variable_list(binary, basic_type, _size) do
    <<first_offset::integer-32-little, rest_bytes::bitstring>> = binary
    num_elements = div(first_offset, @bytes_per_length_offset)

    if Integer.mod(first_offset, @bytes_per_length_offset) != 0 ||
         first_offset < @bytes_per_length_offset do
      {:error, "InvalidListFixedBytesLen"}
    else
      with {:ok, first_offset} <-
             sanitize_offset(first_offset, nil, byte_size(binary), first_offset) do
        decode_variable_list_elements(
          num_elements,
          rest_bytes,
          basic_type,
          first_offset,
          binary,
          first_offset,
          []
        )
        |> Enum.reverse()
        |> flatten_results()
      end
    end
  end

  defp decode_variable_list_elements(
         1 = _num_elements,
         _acc_rest_bytes,
         basic_type,
         offset,
         binary,
         _first_offset,
         results
       ) do
    part = :binary.part(binary, offset, byte_size(binary) - offset)
    [decode(part, basic_type) | results]
  end

  defp decode_variable_list_elements(
         num_elements,
         acc_rest_bytes,
         basic_type,
         offset,
         binary,
         first_offset,
         results
       ) do
    <<next_offset::integer-32-little, rest_bytes::bitstring>> = acc_rest_bytes

    with {:ok, next_offset} <-
           sanitize_offset(next_offset, offset, byte_size(binary), first_offset) do
      part = :binary.part(binary, offset, next_offset - offset)

      decode_variable_list_elements(
        num_elements - 1,
        rest_bytes,
        basic_type,
        next_offset,
        binary,
        first_offset,
        [decode(part, basic_type) | results]
      )
    end
  end

  defp encode_container(container, schemas) do
    {fixed_size_values, fixed_length, variable_values} = analyze_schemas(container, schemas)

    with {:ok, variable_parts} <- encode_schemas(variable_values),
         offsets = calculate_offsets(variable_parts, fixed_length),
         variable_length =
           Enum.reduce(variable_parts, 0, fn part, acc -> byte_size(part) + acc end),
         :ok <- check_length(fixed_length, variable_length),
         {:ok, fixed_parts} <-
           replace_offsets(fixed_size_values, offsets)
           |> encode_schemas do
      (fixed_parts ++ variable_parts)
      |> Enum.join()
      |> then(&{:ok, &1})
    end
  end

  defp analyze_schemas(container, schemas) do
    schemas
    |> Enum.reduce({[], 0, []}, fn {key, schema},
                                   {acc_fixed_size_values, acc_fixed_length, acc_variable_values} ->
      value = Map.fetch!(container, key)

      if variable_size?(schema) do
        {[:offset | acc_fixed_size_values], @bytes_per_length_offset + acc_fixed_length,
         [{value, schema} | acc_variable_values]}
      else
        {[{value, schema} | acc_fixed_size_values], acc_fixed_length + get_fixed_size(schema),
         acc_variable_values}
      end
    end)
  end

  defp encode_schemas(tuple_values) do
    Enum.map(tuple_values, fn {value, schema} -> encode(value, schema) end)
    |> flatten_results()
  end

  defp calculate_offsets(variable_parts, fixed_length) do
    {offsets, _} =
      Enum.reduce(variable_parts, {[], fixed_length}, fn element, {res, acc} ->
        {[{acc, {:int, 32}} | res], byte_size(element) + acc}
      end)

    offsets
  end

  defp replace_offsets(fixed_size_values, offsets) do
    {fixed_size_values, _} =
      Enum.reduce(fixed_size_values, {[], offsets}, &replace_offset/2)

    fixed_size_values
  end

  defp replace_offset(:offset, {acc_fixed_list, [offset | rest_offsets]}),
    do: {[offset | acc_fixed_list], rest_offsets}

  defp replace_offset(element, {acc_fixed_list, acc_offsets_list}),
    do: {[element | acc_fixed_list], acc_offsets_list}

  defp decode_container(binary, module) do
    schemas = module.schema()
    fixed_length = get_fixed_length(schemas)
    <<fixed_binary::binary-size(fixed_length), variable_binary::bitstring>> = binary

    with {:ok, fixed_parts, offsets} <- decode_fixed_section(fixed_binary, schemas, fixed_length),
         {:ok, variable_parts} <- decode_variable_section(variable_binary, offsets) do
      {:ok, struct!(module, fixed_parts ++ variable_parts)}
    end
  end

  defp decode_variable_section(binary, offsets) do
    offsets
    |> Enum.chunk_every(2, 1)
    |> Enum.reduce({binary, []}, fn
      [{offset, {key, schema}}, {next_offset, _}], {rest_bytes, acc_variable_parts} ->
        size = next_offset - offset
        <<chunk::binary-size(size), rest::bitstring>> = rest_bytes
        {rest, [{key, decode(chunk, schema)} | acc_variable_parts]}

      [{_offset, {key, schema}}], {rest_bytes, acc_variable_parts} ->
        {<<>>, [{key, decode(rest_bytes, schema)} | acc_variable_parts]}
    end)
    |> then(fn {<<>>, variable_parts} ->
      flatten_container_results(variable_parts)
    end)
  end

  defp decode_fixed_section(binary, schemas, fixed_length) do
    schemas
    |> Enum.reduce({binary, [], []}, fn {key, schema}, {binary, fixed_parts, offsets} ->
      if variable_size?(schema) do
        <<offset::integer-size(@offset_bits)-little, rest::bitstring>> = binary
        {rest, fixed_parts, [{offset - fixed_length, {key, schema}} | offsets]}
      else
        ssz_fixed_len = get_fixed_size(schema)
        <<chunk::binary-size(ssz_fixed_len), rest::bitstring>> = binary
        {rest, [{key, decode(chunk, schema)} | fixed_parts], offsets}
      end
    end)
    |> then(fn {_rest_bytes, fixed_parts, offsets} ->
      Tuple.append(flatten_container_results(fixed_parts), Enum.reverse(offsets))
    end)
  end

  defp get_fixed_length(schemas) do
    schemas
    |> Stream.map(fn {_key, schema} ->
      if variable_size?(schema) do
        @bytes_per_length_offset
      else
        get_fixed_size(schema)
      end
    end)
    |> Enum.sum()
  end

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

  defp decode_chunk(binary, chunk_size, basic_type) do
    decode_chunk(binary, chunk_size, basic_type, [])
    |> Enum.reverse()
  end

  defp decode_chunk(<<>>, _chunk_size, _basic_type, results), do: results

  defp decode_chunk(binary, chunk_size, basic_type, results) do
    <<element::binary-size(chunk_size), rest::bitstring>> = binary
    decode_chunk(rest, chunk_size, basic_type, [decode(element, basic_type) | results])
  end

  defp flatten_results(results) do
    flatten_results_by(results, &Function.identity/1)
  end

  defp flatten_results_by(results, fun) do
    case Enum.group_by(results, fn {type, _} -> type end, fn {_, result} -> result end) do
      %{error: errors} -> {:error, errors}
      summary -> {:ok, fun.(Map.get(summary, :ok, []))}
    end
  end

  defp flatten_container_results(results) do
    case Enum.group_by(results, fn {_, {type, _}} -> type end, fn {key, {_, result}} ->
           {key, result}
         end) do
      %{error: errors} -> {:error, errors}
      summary -> {:ok, Map.get(summary, :ok, [])}
    end
  end

  defp check_length(fixed_lengths, total_byte_size) do
    if fixed_lengths + total_byte_size <
         2 ** (@bytes_per_length_offset * @bits_per_byte) do
      :ok
    else
      {:error, "invalid lengths"}
    end
  end

  defp get_fixed_size(:bool), do: 1
  defp get_fixed_size({:int, size}), do: div(size, @bits_per_byte)
  defp get_fixed_size({:bytes, size}), do: size

  defp get_fixed_size(module) when is_atom(module) do
    schemas = module.schema()

    schemas
    |> Enum.map(fn {_, schema} -> get_fixed_size(schema) end)
    |> Enum.sum()
  end

  defp variable_size?({:list, _, _}), do: true
  defp variable_size?(:bool), do: false
  defp variable_size?({:int, _}), do: false
  defp variable_size?({:bytes, _}), do: false

  defp variable_size?(module) when is_atom(module) do
    module.schema()
    |> Enum.map(fn {_, schema} -> variable_size?(schema) end)
    |> Enum.any?()
  end

  def length_of_bitlist(bitlist) when is_binary(bitlist) do
    bit_size = bit_size(bitlist)
    <<_::size(bit_size - 8), last_byte>> = bitlist
    bit_size - leading_zeros(<<last_byte>>) - 1
  end

  defp leading_zeros(<<1::1, _::7>>), do: 0
  defp leading_zeros(<<0::1, 1::1, _::6>>), do: 1
  defp leading_zeros(<<0::2, 1::1, _::5>>), do: 2
  defp leading_zeros(<<0::3, 1::1, _::4>>), do: 3
  defp leading_zeros(<<0::4, 1::1, _::3>>), do: 4
  defp leading_zeros(<<0::5, 1::1, _::2>>), do: 5
  defp leading_zeros(<<0::6, 1::1, _::1>>), do: 6
  defp leading_zeros(<<0::7, 1::1>>), do: 7
  defp leading_zeros(<<0::8>>), do: 8

  @spec remove_trailing_bit(binary()) :: bitstring()
  defp remove_trailing_bit(<<1::1, rest::7>>), do: <<rest::7>>
  defp remove_trailing_bit(<<0::1, 1::1, rest::6>>), do: <<rest::6>>
  defp remove_trailing_bit(<<0::2, 1::1, rest::5>>), do: <<rest::5>>
  defp remove_trailing_bit(<<0::3, 1::1, rest::4>>), do: <<rest::4>>
  defp remove_trailing_bit(<<0::4, 1::1, rest::3>>), do: <<rest::3>>
  defp remove_trailing_bit(<<0::5, 1::1, rest::2>>), do: <<rest::2>>
  defp remove_trailing_bit(<<0::6, 1::1, rest::1>>), do: <<rest::1>>
  defp remove_trailing_bit(<<0::7, 1::1>>), do: <<0::0>>
  defp remove_trailing_bit(<<0::8>>), do: <<0::0>>

  defp size_of(:bool), do: @bytes_per_boolean

  defp size_of({:int, size}), do: size |> div(@bits_per_byte)

  defp pack_basic_type_list(list, schema) do
    list
    |> Enum.reduce(<<>>, fn x, acc ->
      {:ok, encoded} = encode(x, schema)
      acc <> encoded
    end)
    |> pack_bytes()
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

  defp next_pow_of_two(len) when is_integer(len) and len >= 0 do
    if len == 0 do
      0
    else
      n = ((len <<< 1) - 1) |> :math.log2() |> trunc()
      2 ** n
    end
  end

  defp replace_chunk(chunks, start, new_chunk) do
    <<left::binary-size(start), _::size(@bits_per_chunk), right::binary>> =
      chunks

    <<left::binary, new_chunk::binary, right::binary>>
  end

  defp get_chunks_len(chunks) do
    chunks |> byte_size() |> div(@bytes_per_chunk)
  end

  defp compute_pow(value) do
    :math.log2(value) |> trunc()
  end
end
