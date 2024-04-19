defmodule Unit.Validator.BlockBuilderTest do
  @moduledoc false

  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias LambdaEthereumConsensus.Validator.BlockBuilder
  alias LambdaEthereumConsensus.Validator.BuildBlockRequest
  alias Types.BeaconBlockBody
  alias Types.BeaconState
  alias Types.SignedBeaconBlock

  use ExUnit.Case

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

    proposed_slot = pre_state.slot + 1

    {:ok, block_request} =
      %BuildBlockRequest{
        slot: proposed_slot,
        parent_root: spec_block.message.parent_root,
        proposer_index: 63,
        graffiti_message: "",
        privkey: privkey
      }
      |> BuildBlockRequest.validate(pre_state)

    {:ok, mid_state} = StateTransition.process_slots(pre_state, proposed_slot)

    {:ok, block} =
      BlockBuilder.construct_beacon_block(
        mid_state,
        block_request,
        spec_block.message.body.execution_payload,
        spec_block.message.body.eth1_data
      )

    assert block.body.randao_reveal == spec_block.message.body.randao_reveal

    {:ok, signed_block} = BlockBuilder.seal_block(pre_state, block, privkey)

    assert signed_block.signature == spec_block.signature

    assert {:ok, _} = StateTransition.state_transition(pre_state, signed_block, true)
  end

  test "prove commitments" do
    spec_block =
      SpecTestUtils.read_ssz_from_file!(
        "test/fixtures/validator/proposer/empty_block.ssz_snappy",
        SignedBeaconBlock
      )

    commitment = <<0::384>>
    body = %{spec_block.message.body | blob_kzg_commitments: [commitment]}
    body_root = SszEx.hash_tree_root!(body, BeaconBlockBody)

    [proof] = BlockBuilder.compute_inclusion_proofs(body)

    assert length(proof) == 9

    commitment_root = SszEx.hash_tree_root!(commitment, TypeAliases.kzg_commitment())

    # Manually computed generalized index of the commitment in the body
    index = 0b101100000

    valid? =
      Predicates.valid_merkle_branch?(commitment_root, proof, length(proof), index, body_root)

    assert valid?
  end
end
