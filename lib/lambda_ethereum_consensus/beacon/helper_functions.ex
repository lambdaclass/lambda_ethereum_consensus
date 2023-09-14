defmodule LambdaEthereumConsensus.Beacon.HelperFunctions do
  @doc """
  Return the 32-byte fork data root for the ``current_version`` and ``genesis_validators_root``.
  This is used primarily in signature domains to avoid collisions across forks/chains.
  """
  @spec compute_fork_data_root(SszTypes.version(), SszTypes.root()) :: SszTypes.root()
  def compute_fork_data_root(current_version, genesis_validators_root) do
    Ssz.hash_tree_root(%SszTypes.ForkData{
      current_version: current_version,
      genesis_validators_root: genesis_validators_root
    })
  end

  @doc """
  Return the 4-byte fork digest for the ``current_version`` and ``genesis_validators_root``.
  This is a digest primarily used for domain separation on the p2p layer.
  4-bytes suffices for practical separation of forks/chains.
  """
  @spec compute_fork_digest(SszTypes.version(), SszTypes.root()) :: SszTypes.fork_digest()
  def compute_fork_digest(current_version, genesis_validators_root) do
    compute_fork_data_root(current_version, genesis_validators_root)
    |> binary_part(0, 4)
  end
end
