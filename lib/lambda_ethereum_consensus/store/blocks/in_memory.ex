defmodule LambdaEthereumConsensus.Store.Blocks.InMemory do
  @moduledoc false
  alias Types.SignedBeaconBlock

  @behaviour LambdaEthereumConsensus.Store.BlocksImpl

  defstruct inner: %{}
  @type t() :: %__MODULE__{inner: %{Types.root() => SignedBeaconBlock.t()}}

  def new, do: %__MODULE__{}

  ##########################
  ### Public API
  ##########################

  @impl true
  @spec store_block(t(), Types.root(), SignedBeaconBlock.t()) :: t()
  def store_block(%{inner: blocks} = state, block_root, signed_block) do
    new_blocks = Map.put(blocks, block_root, signed_block)
    %{state | inner: new_blocks}
  end

  @impl true
  @spec get_block(t(), Types.root()) :: SignedBeaconBlock.t() | nil
  def get_block(%{inner: blocks}, block_root), do: Map.get(blocks, block_root)
end
