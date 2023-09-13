defmodule LambdaEthereumConsensus.Store.BlockStore do
  @moduledoc """
  Storing and retrieval of blocks.
  """

  @prefix "block"

  @spec store_block(SszTypes.BeaconBlock.t()) :: any
  def store_block(%SszTypes.BeaconBlock{} = block) do
    key = @prefix <> block.state_root
    {:ok, encoded_block} = Ssz.to_ssz(block)
    LambdaEthereumConsensus.Store.Db.put(key, encoded_block)
  end

  @spec get_block(binary()) :: {:ok, struct()} | {:error, String.t()} | :not_found
  def get_block(state_root) do
    key = @prefix <> state_root

    case LambdaEthereumConsensus.Store.Db.get(key) do
      :not_found ->
        :not_found

      {:ok, block} ->
        Ssz.from_ssz(block, SszTypes.BeaconBlock)
    end
  end
end
