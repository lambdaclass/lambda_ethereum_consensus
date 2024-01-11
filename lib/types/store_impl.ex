defprotocol Types.StoreImpl do
  @moduledoc """
  Protocol for the `Store`'s underlying storage implementation.
  """
  alias Types.BeaconBlock
  alias Types.BeaconState
  alias Types.SignedBeaconBlock

  ## Blocks

  @spec store_block(t(), Types.root(), SignedBeaconBlock.t()) :: any()
  def store_block(t, block_root, signed_block)

  @spec get_block(t(), Types.root()) :: BeaconBlock.t() | nil
  def get_block(t, block_root)

  @spec get_blocks(t()) :: Enumerable.t(BeaconBlock.t())
  def get_blocks(t)

  ## Block states

  @spec store_state(t(), Types.root(), BeaconState.t()) :: any()
  def store_state(t, block_root, beacon_state)

  @spec get_state(t(), Types.root()) :: BeaconState.t() | nil
  def get_state(t, block_root)
end
