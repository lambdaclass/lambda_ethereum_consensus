defmodule LambdaEthereumConsensus.Store.State.BlockRootBySlot do
  @moduledoc """
  KvSchema that stores block roots indexed by slots.
  """

  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.KvSchema

  use KvSchema, prefix: "state_by_slot"

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

  @spec get_last_block_root() :: {:ok, Types.root()} | {:error, binary()}
  def get_last_block_root() do
    with {:ok, last_key} <- do_encode_key(0xFFFFFFFFFFFFFFFF),
         {:ok, it} <- Db.iterate(),
         {:ok, _key, _value} <- Exleveldb.iterator_move(it, last_key),
         {:ok, @prefix <> _slot, root} <- Exleveldb.iterator_move(it, :prev),
         :ok <- Exleveldb.iterator_close(it) do
      {:ok, root}
    else
      {:ok, _key, _value} -> :not_found
      {:error, :invalid_iterator} -> :not_found
    end
  end
end
