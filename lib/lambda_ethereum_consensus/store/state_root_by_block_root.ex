defmodule LambdaEthereumConsensus.Store.StateRootByBlockRoot do
  @moduledoc """
  KvSchema that stores StateInfo roots indexed by BeaconBlock roots.
  """

  alias LambdaEthereumConsensus.Store.KvSchema
  use KvSchema, prefix: "state_info_root"

  @impl KvSchema
  @spec encode_key(Types.root()) :: {:ok, binary()}
  def encode_key(root) when is_binary(root), do: {:ok, root}

  @impl KvSchema
  @spec decode_key(binary()) :: {:ok, Types.root()}
  def decode_key(root) when is_binary(root), do: {:ok, root}

  @impl KvSchema
  @spec encode_value(Types.root()) :: {:ok, binary()}
  def encode_value(root) when is_binary(root), do: {:ok, root}

  @impl KvSchema
  @spec decode_value(binary()) :: {:ok, Types.root()}
  def decode_value(root) when is_binary(root), do: {:ok, root}
end
