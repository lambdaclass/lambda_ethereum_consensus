defmodule Unit.ForkDigestTest do
  @moduledoc """
  Tests for EIP-7892 epoch-based compute_fork_digest, which XORs the base fork digest
  with a SHA-256 hash of the blob parameters for all epochs.

  Algorithm (consensus-specs/specs/fulu/beacon-chain.md):
    fork_version   = compute_fork_version(epoch)
    base_digest    = compute_fork_data_root(fork_version, genesis_validators_root)
    blob_params    = get_blob_parameters(epoch)   # fallback: (ELECTRA_FORK_EPOCH, MAX_BLOBS_PER_BLOCK_ELECTRA)
    mask           = sha256(le_uint64(blob_params.epoch) ++ le_uint64(blob_params.max_blobs_per_block))
    fork_digest    = xor(base_digest, mask)[:4]
  """

  use ExUnit.Case
  alias LambdaEthereumConsensus.StateTransition.Misc

  # Mainnet genesis validators root (from genesis state)
  @mainnet_gvr Base.decode16!("4B363DB94E286120D76EB905340FDD4E54BFE9F06BF33FF6CF5AD27F511BFE95")

  setup_all do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.merge(config: MainnetConfig, genesis_validators_root: @mainnet_gvr)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))
  end

  @fulu_fork_epoch 411_392
  # First BLOB_SCHEDULE entry (epoch 412672 with 15 blobs)
  @first_bpo_epoch 412_672

  test "EIP-7892: Fulu digest is XOR of base digest and SHA256(blob_params)" do
    # Verify the algorithm is applied correctly by replicating it step by step.
    gvr = @mainnet_gvr
    epoch = @fulu_fork_epoch

    fork_version = ChainSpec.get_fork_version_for_epoch(epoch)
    base_digest = Misc.compute_fork_data_root(fork_version, gvr)
    blob_params = Misc.get_blob_parameters(epoch)

    input =
      <<blob_params.epoch::little-unsigned-size(64),
        blob_params.max_blobs_per_block::little-unsigned-size(64)>>

    mask = :crypto.hash(:sha256, input)
    expected = :crypto.exor(binary_part(base_digest, 0, 4), binary_part(mask, 0, 4))

    assert Misc.compute_fork_digest(gvr, epoch) == expected
  end

  test "EIP-7892: Fulu fallback blob params are ELECTRA values at FULU_FORK_EPOCH" do
    # At Fulu activation no BLOB_SCHEDULE entry exists yet (first is at 412672),
    # so the fallback (ELECTRA_FORK_EPOCH, MAX_BLOBS_PER_BLOCK_ELECTRA) is used.
    blob_params = Misc.get_blob_parameters(@fulu_fork_epoch)
    assert blob_params.epoch == ChainSpec.get("ELECTRA_FORK_EPOCH")
    assert blob_params.max_blobs_per_block == ChainSpec.get("MAX_BLOBS_PER_BLOCK_ELECTRA")
  end

  test "digest is consistent across the same blob params period" do
    # Epochs 411392..412671 all use the Electra fallback (same blob params, same fork version),
    # so they produce the same fork digest.
    digest_at_activation = Misc.compute_fork_digest(@mainnet_gvr, @fulu_fork_epoch)
    digest_before_bpo = Misc.compute_fork_digest(@mainnet_gvr, @first_bpo_epoch - 1)
    assert digest_at_activation == digest_before_bpo
  end

  test "first BPO epoch produces a different digest than FULU_FORK_EPOCH" do
    # At epoch 412672, the BLOB_SCHEDULE kicks in (15 blobs), changing the blob params
    # hash, so the fork digest changes — ensuring nodes on different blob schedules disconnect.
    digest_at_fulu = Misc.compute_fork_digest(@mainnet_gvr, @fulu_fork_epoch)
    digest_at_bpo = Misc.compute_fork_digest(@mainnet_gvr, @first_bpo_epoch)
    assert digest_at_fulu != digest_at_bpo
  end

  test "pre-Fulu epoch uses a different fork version, producing a different digest" do
    electra_epoch = 364_032
    digest_electra = Misc.compute_fork_digest(@mainnet_gvr, electra_epoch)
    digest_fulu = Misc.compute_fork_digest(@mainnet_gvr, @fulu_fork_epoch)
    assert digest_electra != digest_fulu
  end

  test "next_digest_change_epoch returns first BLOB_SCHEDULE epoch after current" do
    # From FULU_FORK_EPOCH, the next change is the first BPO at 412672
    assert Misc.next_digest_change_epoch(@fulu_fork_epoch) == @first_bpo_epoch
  end

  test "next_digest_change_epoch returns second BPO when past first" do
    second_bpo_epoch = 419_072
    assert Misc.next_digest_change_epoch(@first_bpo_epoch) == second_bpo_epoch
  end

  test "next_digest_change_epoch returns nil when past all scheduled BPOs" do
    assert Misc.next_digest_change_epoch(500_000) == nil
  end
end
