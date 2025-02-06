defmodule Types.StateInfo do
  @moduledoc """
  Struct to hold state and metadata for easier db storing:
  - beacon_state: A beacon state.
  - root: The hash tree root of the state, so that we don't recalculate it before saving.
  - encoded: The ssz encoded version of the state. It's common that we save a
    state after
  Warning: Do not modify this manually. If you do, you may need to re-encode the beacon state using `from_beacon_state`.
  """
  alias Types.BeaconBlockHeader
  alias Types.BeaconState

  defstruct [:root, :beacon_state, :encoded, :block_root]

  @type t :: %__MODULE__{
          beacon_state: Types.BeaconState.t(),
          root: Types.root(),
          encoded: binary(),
          block_root: Types.root()
        }

  @spec from_beacon_state(Types.BeaconState.t(), keyword()) :: {:ok, t()} | {:error, binary()}
  def from_beacon_state(%BeaconState{} = state, fields \\ []) do
    state_root = Ssz.hash_tree_root!(state)

    slots_per_historical_root = ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")
    cache_index = rem(state.slot, slots_per_historical_root)
    roots = List.replace_at(state.state_roots, cache_index, state_root)
    state = %BeaconState{state | state_roots: roots}

    # Cache latest block header state root
    state =
      if state.latest_block_header.state_root == <<0::256>> do
        block_header = %BeaconBlockHeader{
          state.latest_block_header
          | state_root: state_root
        }

        %BeaconState{state | latest_block_header: block_header}
      else
        state
      end

    # Cache block root
    {:ok, block_root} =
      fetch_lazy(fields, :block_root, fn ->
        # NOTE: due to how SSZ-hashing works, hash(block) == hash(header)
        Ssz.hash_tree_root(state.latest_block_header)
      end)

    roots = List.replace_at(state.block_roots, cache_index, block_root)

    state = %BeaconState{state | block_roots: roots}

    with {:ok, encoded} <- fetch_lazy(fields, :encoded, fn -> Ssz.to_ssz(state) end) do
      {:ok, from_beacon_state(state, encoded, state_root, block_root)}
    end
  end

  @spec from_beacon_state(Types.BeaconState.t(), binary(), Types.root(), Types.root()) :: t()
  def from_beacon_state(%BeaconState{} = state, encoded, state_root, block_root) do
    %__MODULE__{root: state_root, beacon_state: state, encoded: encoded, block_root: block_root}
  end

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = state_info) do
    {state_info.encoded, state_info.root, state_info.block_root} |> :erlang.term_to_binary()
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, binary()}
  def decode(bin) do
    with {:ok, encoded, root, block_root} <- :erlang.binary_to_term(bin) |> validate_term(),
         {:ok, beacon_state} <- Ssz.from_ssz(encoded, BeaconState) do
      {:ok,
       %__MODULE__{
         beacon_state: beacon_state,
         root: root,
         block_root: block_root,
         encoded: encoded
       }}
    end
  end

  defp fetch_lazy(keyword, key, fun) do
    with :error <- Keyword.fetch(keyword, key), do: fun.()
  end

  @spec validate_term(term()) :: {:ok, binary(), Types.root(), Types.root()} | {:error, binary()}
  defp validate_term({ssz_encoded, root, block_root})
       when is_binary(ssz_encoded) and is_binary(root) and is_binary(block_root) do
    {:ok, ssz_encoded, root, block_root}
  end

  defp validate_term(other) do
    {:error,
     "Error when decoding state info binary. Expected a {binary(), binary()} tuple. Found: #{inspect(other)}"}
  end
end
