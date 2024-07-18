defmodule LambdaEthereumConsensus.Store.StateInfoByRoot do
  @moduledoc """
  KvSchema that stores StateInfos indexed by BeaconState roots.
  """

  alias LambdaEthereumConsensus.Store.KvSchema
  alias Types.StateInfo
  use KvSchema, prefix: "state_root_by_block_root"

  @impl KvSchema
  @spec encode_key(Types.root()) :: {:ok, binary()}
  def encode_key(root) when is_binary(root), do: {:ok, root}

  @impl KvSchema
  @spec decode_key(binary()) :: {:ok, Types.root()}
  def decode_key(root) when is_binary(root), do: {:ok, root}

  @impl KvSchema
  @spec encode_value(StateInfo.t()) :: {:ok, binary()} | {:error, binary()}
  def encode_value(%StateInfo{} = state_info), do: {:ok, StateInfo.encode(state_info)}

  @impl KvSchema
  @spec decode_value(binary()) :: {:ok, StateInfo.t()} | {:error, binary()}
  def decode_value(encoded_state) when is_binary(encoded_state),
    do: {:ok, StateInfo.decode(encoded_state)}
end
