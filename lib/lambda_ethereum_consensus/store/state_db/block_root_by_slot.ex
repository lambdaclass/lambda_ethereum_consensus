defmodule LambdaEthereumConsensus.Store.StateDb.BlockRootBySlot do
  @moduledoc """
  KvSchema that stores block roots indexed by slots.
  """
  alias LambdaEthereumConsensus.Store.KvSchema
  require Logger
  use KvSchema, prefix: "statedb_block_root_by_slot"

  @impl KvSchema
  @spec encode_key(Types.slot()) :: {:ok, binary()} | {:error, binary()}
  def encode_key(slot), do: {:ok, <<slot::64>>}

  @impl KvSchema
  @spec decode_key(binary()) :: {:ok, integer()} | {:error, binary()}
  def decode_key(<<slot::64>>), do: {:ok, slot}

  def decode_key(other) do
    {:error, "[Block by slot] Could not decode slot, not 64 bit integer: #{other}"}
  end

  @impl KvSchema
  @spec encode_value(Types.root()) :: {:ok, Types.root()} | {:error, binary()}
  def encode_value(<<_::256>> = root), do: {:ok, root}

  @impl KvSchema
  @spec decode_value(Types.root()) :: {:ok, Types.root()} | {:error, binary()}
  def decode_value(<<_::256>> = root), do: {:ok, root}

  @spec get_last_slot_block_root() :: {:ok, Types.root()} | :not_found
  def get_last_slot_block_root() do
    with {:ok, first_slot} <- first_key() do
      fold_keys(
        first_slot,
        nil,
        fn slot, _acc ->
          case get(slot) do
            {:ok, block_root} ->
              block_root

            other ->
              Logger.error(
                "[Block pruning] Failed to find last slot root #{inspect(slot)}. Reason: #{inspect(other)}"
              )
          end
        end,
        direction: :next,
        include_first: true
      )
    end
  end
end
