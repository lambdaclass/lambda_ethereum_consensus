defmodule LambdaEthereumConsensus.Store.StateDb.StateRootByBlockRoot do
  @moduledoc """
  KvSchema that stores state roots indexed by BeaconBlock roots.
  """

  alias LambdaEthereumConsensus.Store.KvSchema
  use KvSchema, prefix: "statedb_state_root_by_block_root"

  @impl KvSchema
  @spec encode_key(Types.root()) :: {:ok, binary()}
  def encode_key(<<_::256>> = root), do: {:ok, root}

  @impl KvSchema
  @spec decode_key(Types.root()) :: {:ok, Types.root()}
  def decode_key(<<_::256>> = root), do: {:ok, root}

  @impl KvSchema
  @spec encode_value(Types.root()) :: {:ok, binary()}
  def encode_value(<<_::256>> = root), do: {:ok, root}

  @impl KvSchema
  @spec decode_value(Types.root()) :: {:ok, Types.root()} | {:error, binary()}
  def decode_value(<<_::256>> = root), do: {:ok, root}
end
