defmodule LambdaEthereumConsensus.Store.BlocksImpl do
  @moduledoc false
  alias Types.SignedBeaconBlock

  @type t() :: struct()

  @callback store_block(t(), Types.root(), SignedBeaconBlock.t()) :: t()
  @callback get_block(t(), Types.root()) :: SignedBeaconBlock.t() | nil
end
