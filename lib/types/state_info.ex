defmodule Types.StateInfo do
  @moduledoc """
  Struct to hold state and metadata for easier db storing:
  - beacon_state: A beacon state.
  - root: The hash tree root of the state, so that we don't recalculate it before saving.
  - encoded: The ssz encoded version of the state. It's common that we save a
    state after
  Warning: Do not modify this manually. If you do, you may need to re-encode the beacon state using `from_beacon_state`.
  """
  alias Types.BeaconState

  defstruct [:root, :beacon_state, :encoded, :block_root, field_hashes: %{}]

  @type t :: %__MODULE__{
          beacon_state: Types.BeaconState.t(),
          root: Types.root(),
          encoded: binary() | nil,
          block_root: Types.root(),
          field_hashes: %{non_neg_integer() => binary()}
        }

  @spec from_beacon_state(Types.BeaconState.t(), keyword()) :: {:ok, t()} | {:error, binary()}
  def from_beacon_state(%BeaconState{} = state, fields \\ []) do
    cached_field_hashes = Keyword.get(fields, :cached_field_hashes, %{})

    with {:ok, block_root} <-
           fetch_lazy(fields, :block_root, fn ->
             # NOTE: due to how SSZ-hashing works, hash(block) == hash(header)
             Ssz.hash_tree_root(state.latest_block_header)
           end),
         {:ok, root, field_hashes_binary} <-
           Ssz.hash_beacon_state_cached(state, cached_field_hashes) do
      field_hashes = parse_field_hashes(field_hashes_binary, 0, %{})

      {:ok,
       %__MODULE__{
         root: root,
         beacon_state: state,
         block_root: block_root,
         field_hashes: field_hashes
       }}
    end
  end

  # Parse concatenated 32-byte hashes into a map of %{field_index => hash}
  defp parse_field_hashes(<<>>, _idx, acc), do: acc

  defp parse_field_hashes(<<hash::binary-size(32), rest::binary>>, idx, acc) do
    parse_field_hashes(rest, idx + 1, Map.put(acc, idx, hash))
  end

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{encoded: nil} = state_info) do
    {:ok, encoded} = Ssz.to_ssz(state_info.beacon_state)

    {encoded, state_info.root, state_info.block_root, state_info.field_hashes}
    |> :erlang.term_to_binary()
  end

  def encode(%__MODULE__{} = state_info) do
    {state_info.encoded, state_info.root, state_info.block_root, state_info.field_hashes}
    |> :erlang.term_to_binary()
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, binary()}
  def decode(bin) do
    with {:ok, encoded, root, block_root, field_hashes} <-
           :erlang.binary_to_term(bin) |> validate_term(),
         {:ok, beacon_state} <- Ssz.from_ssz(encoded, BeaconState) do
      {:ok,
       %__MODULE__{
         beacon_state: beacon_state,
         root: root,
         block_root: block_root,
         encoded: encoded,
         field_hashes: field_hashes
       }}
    end
  end

  defp fetch_lazy(keyword, key, fun) do
    with :error <- Keyword.fetch(keyword, key), do: fun.()
  end

  @spec validate_term(term()) ::
          {:ok, binary(), Types.root(), Types.root(), %{non_neg_integer() => binary()}}
          | {:error, binary()}
  defp validate_term({ssz_encoded, root, block_root, field_hashes})
       when is_binary(ssz_encoded) and is_binary(root) and is_binary(block_root) and
              is_map(field_hashes) do
    {:ok, ssz_encoded, root, block_root, field_hashes}
  end

  # Backwards compatibility: old 3-tuple format without field_hashes
  defp validate_term({ssz_encoded, root, block_root})
       when is_binary(ssz_encoded) and is_binary(root) and is_binary(block_root) do
    {:ok, ssz_encoded, root, block_root, %{}}
  end

  defp validate_term(other) do
    {:error,
     "Error when decoding state info binary. Expected a {binary(), binary(), binary(), map()} tuple. Found: #{inspect(other)}"}
  end
end
