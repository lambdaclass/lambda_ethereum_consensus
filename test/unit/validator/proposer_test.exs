defmodule Unit.Validator.ProposerTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.Validator.Proposer
  alias Types.BeaconState
  alias Types.SignedBeaconBlock

  setup_all do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.put(:config, MinimalConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))
  end

  test "construct block" do
    pre_state =
      SpecTestUtils.read_ssz_from_file!(
        "test/spec/vectors/tests/minimal/deneb/sanity/blocks/pyspec_tests/empty_block_transition/pre.ssz_snappy",
        BeaconState
      )

    spec_block =
      SpecTestUtils.read_ssz_from_file!(
        "test/spec/vectors/tests/minimal/deneb/sanity/blocks/pyspec_tests/empty_block_transition/blocks_0.ssz_snappy",
        SignedBeaconBlock
      )

    # This private key is taken from the spec test vectors
    privkey =
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 64>>

    {:ok, signed_block} = Proposer.construct_block(pre_state, privkey)
    assert signed_block.message.body.randao_reveal == spec_block.message.body.randao_reveal
    assert signed_block.signature == spec_block.signature
  end
end
