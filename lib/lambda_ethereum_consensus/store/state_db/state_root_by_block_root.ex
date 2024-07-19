defmodule LambdaEthereumConsensus.Store.StateDb.StateRootByBlockRoot do
  @moduledoc """
  KvSchema that stores StateInfo roots indexed by BeaconBlock roots.
  """

  alias LambdaEthereumConsensus.Store.KvSchema
  use KvSchema, prefix: "state_info_root"

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
