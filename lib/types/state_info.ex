defmodule Types.StateInfo do
  @moduledoc """
  Struct to hold state and metadata for easier db storing:
  - beacon_state: A beacon state.
  - root: The hash tree root of the state, so that we don't recalculate it before saving.
  - encoded: The ssz encoded version of the state. It's common that we save a
    state after
  """
  alias Types.BeaconState

  defstruct [:root, :beacon_state, :encoded, :block_root]

  @type t :: %__MODULE__{
          beacon_state: Types.BeaconState.t(),
          root: Types.root(),
          encoded: binary(),
          block_root: Types.root()
        }

  @spec from_beacon_state(Types.BeaconState.t(), keyword()) :: Types.StateInfo.t()
  def from_beacon_state(%BeaconState{} = state, fields \\ []) do
    encoded = Keyword.get_lazy(fields, :encoded, fn -> Ssz.to_ssz(state) end)

    block_root =
      Keyword.get_lazy(fields, :block_root, fn ->
        # NOTE: due to how SSZ-hashing works, hash(block) == hash(header)
        Ssz.hash_tree_root(state.latest_block_header)
      end)

    from_beacon_state(state, encoded, block_root)
  end

  @spec from_beacon_state(Types.BeaconState.t(), binary(), Types.root()) :: t()
  def from_beacon_state(%BeaconState{} = state, encoded, block_root) do
    root = Ssz.hash_tree_root!(state)
    %__MODULE__{root: root, beacon_state: state, encoded: encoded, block_root: block_root}
  end

  def encode(%__MODULE__{} = state_info) do
    {state_info.encoded, state_info.root} |> :erlang.term_to_binary()
  end

  def decode(bin, block_root) do
    with {:ok, encoded, root} <- :erlang.binary_to_term(bin) |> validate_term(),
         {:ok, beacon_state} <- Ssz.from_ssz(bin, BeaconState) do
      %__MODULE__{
        beacon_state: beacon_state,
        root: root,
        block_root: block_root,
        encoded: encoded
      }
    end
  end

  defp validate_term({ssz_encoded, root}) when is_binary(ssz_encoded) and is_binary(root) do
    {:ok, ssz_encoded, root}
  end

  defp validate_term(other) do
    {:error,
     "Error when decoding state info binary. Expected a {binary(), binary()} tuple. Found: #{other}"}
  end
end
