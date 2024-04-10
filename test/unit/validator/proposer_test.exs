defmodule Unit.Validator.ProposerTests do
  @moduledoc false
  use ExUnit.Case

  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.Validator.BlockRequest
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
    privkey = <<0::248, 64>>

    block_request = %BlockRequest{
      slot: pre_state.slot + 1,
      parent_root: spec_block.message.parent_root,
      proposer_index: 63,
      graffiti_message: "",
      eth1_data: %Types.Eth1Data{
        deposit_root: <<0::256>>,
        deposit_count: 64,
        block_hash: <<0::256>>
      },
      execution_payload: spec_block.message.body.execution_payload,
      privkey: privkey
    }

    {:ok, signed_block} = Proposer.construct_block(pre_state, block_request)

    assert signed_block.message.body.randao_reveal == spec_block.message.body.randao_reveal
    assert signed_block.signature == spec_block.signature

    assert {:ok, _} = StateTransition.state_transition(pre_state, signed_block, true)
  end
end
