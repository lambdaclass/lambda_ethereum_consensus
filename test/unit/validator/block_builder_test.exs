defmodule Unit.Validator.BlockBuilderTest do
  @moduledoc false

  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.Validator.BlockBuilder
  alias LambdaEthereumConsensus.Validator.BuildBlockRequest
  alias Types.BeaconState
  alias Types.SignedBeaconBlock

  use ExUnit.Case
  use Patch

  setup_all do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.put(:config, MinimalConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))
  end

  test "construct block" do
    expose(BlockBuilder, construct_block: 4)

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
    privkey = <<0::248, 64>>

    block_request = %BuildBlockRequest{
      slot: pre_state.slot + 1,
      parent_root: spec_block.message.parent_root,
      proposer_index: 63,
      graffiti_message: "",
      privkey: privkey
    }

    {:ok, signed_block} =
      private(
        BlockBuilder.construct_block(
          pre_state,
          block_request,
          spec_block.message.body.execution_payload,
          spec_block.message.body.eth1_data
        )
      )

    assert signed_block.message.body.randao_reveal == spec_block.message.body.randao_reveal
    assert signed_block.signature == spec_block.signature

    assert {:ok, _} = StateTransition.state_transition(pre_state, signed_block, true)
  end
end
