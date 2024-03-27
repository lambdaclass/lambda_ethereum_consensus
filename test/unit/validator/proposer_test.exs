defmodule Unit.Validator.ProposerTests do
  @moduledoc false
  use ExUnit.Case

  alias LambdaEthereumConsensus.StateTransition
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
        "test/fixtures/validator/proposer/beacon_state.ssz_snappy",
        BeaconState
      )

    spec_block =
      SpecTestUtils.read_ssz_from_file!(
        "test/fixtures/validator/proposer/empty_block.ssz_snappy",
        SignedBeaconBlock
      )

    # This private key is taken from the spec test vectors
    privkey =
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 64>>

    validator_index = 63

    {:ok, pre} = StateTransition.process_slots(pre_state, 1)

    {:ok, signed_block} = Proposer.construct_block(pre, validator_index, privkey)
    assert signed_block.message.body.randao_reveal == spec_block.message.body.randao_reveal
    assert signed_block.signature == spec_block.signature

    assert {:ok, _} = StateTransition.state_transition(pre_state, signed_block, true)
  end
end
