defmodule SanityTestRunner do
  @moduledoc """
  Runner for Sanity test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/sanity
  """

  use ExUnit.CaseTemplate
  use TestRunner

  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.Utils.Diff
  alias Types.BeaconState

  use HardForkAliasInjection

  @disabled_block_cases [
    # "activate_and_partial_withdrawal_max_effective_balance",
    # "activate_and_partial_withdrawal_overdeposit",
    # "attestation",
    # "attester_slashing",
    # "balance_driven_status_transitions",
    # "bls_change",
    # "deposit_and_bls_change",
    # "deposit_in_block",
    # "deposit_top_up",
    # "duplicate_attestation_same_block",
    # "invalid_is_execution_enabled_false",
    # "empty_block_transition",
    # "empty_block_transition_large_validator_set",
    # "empty_block_transition_no_tx",
    # "empty_block_transition_randomized_payload",
    # "empty_epoch_transition",
    # "empty_epoch_transition_large_validator_set",
    # "empty_epoch_transition_not_finalizing",
    # "eth1_data_votes_consensus",
    # "eth1_data_votes_no_consensus",
    # "exit_and_bls_change",
    # "full_random_operations_0",
    # "full_random_operations_1",
    # "full_random_operations_2",
    # "full_random_operations_3",
    # "full_withdrawal_in_epoch_transition",
    # "high_proposer_index",
    # "historical_batch",
    # "inactivity_scores_full_participation_leaking",
    # "inactivity_scores_leaking",
    # "invalid_all_zeroed_sig",
    # "invalid_duplicate_attester_slashing_same_block",
    # "invalid_duplicate_bls_changes_same_block",
    # "invalid_duplicate_deposit_same_block",
    # "invalid_duplicate_proposer_slashings_same_block",
    # "invalid_duplicate_validator_exit_same_block",
    # "invalid_incorrect_block_sig",
    # "invalid_incorrect_proposer_index_sig_from_expected_proposer",
    # "invalid_incorrect_proposer_index_sig_from_proposer_index",
    # "invalid_incorrect_state_root",
    # "invalid_only_increase_deposit_count",
    # "invalid_parent_from_same_slot",
    # "invalid_prev_slot_block_transition",
    # "invalid_same_slot_block_transition",
    # "invalid_similar_proposer_slashings_same_block",
    # "invalid_two_bls_changes_of_different_addresses_same_validator_same_block",
    # "invalid_withdrawal_fail_second_block_payload_isnt_compatible",
    # "is_execution_enabled_false",
    # "many_partial_withdrawals_in_epoch_transition",
    # "multiple_attester_slashings_no_overlap",
    # "multiple_attester_slashings_partial_overlap",
    # "multiple_different_proposer_slashings_same_block",
    # "multiple_different_validator_exits_same_block",
    # "partial_withdrawal_in_epoch_transition",
    # "proposer_after_inactive_index",
    # "proposer_self_slashing",
    # "proposer_slashing",
    # "skipped_slots",
    # "slash_and_exit_diff_index",
    # "slash_and_exit_same_index"
    # "sync_committee_committee__empty",
    # "sync_committee_committee__full",
    # "sync_committee_committee__half",
    # "sync_committee_committee_genesis__empty",
    # "sync_committee_committee_genesis__full",
    # "sync_committee_committee_genesis__half",
    # "top_up_and_partial_withdrawable_validator",
    # "top_up_to_fully_withdrawn_validator",
    # "voluntary_exit",
    # "withdrawal_success_two_blocks"
  ]

  @disabled_slot_cases [
    # "empty_epoch",
    # "slots_1",
    # "slots_2",
    # "over_epoch_boundary",
    # NOTE: too long to run in CI
    # TODO: optimize
    "historical_accumulator"
    # "double_empty_epoch"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: "capella", handler: "blocks", case: testcase}) do
    Enum.member?(@disabled_block_cases, testcase)
  end

  def skip?(%SpecTestCase{fork: "capella", handler: "slots", case: testcase}) do
    Enum.member?(@disabled_slot_cases, testcase)
  end

  def skip?(%SpecTestCase{fork: "deneb", handler: "blocks", case: testcase}) do
    Enum.member?(@disabled_block_cases, testcase)
  end

  def skip?(%SpecTestCase{fork: "deneb", handler: "slots", case: testcase}) do
    Enum.member?(@disabled_slot_cases, testcase)
  end

  def skip?(_), do: true

  @impl TestRunner
  def run_test_case(%SpecTestCase{handler: "slots"} = testcase) do
    # TODO process meta.yaml
    case_dir = SpecTestCase.dir(testcase)

    pre = SpecTestUtils.read_ssz_from_file!(case_dir <> "/pre.ssz_snappy", BeaconState)
    post = SpecTestUtils.read_ssz_from_optional_file!(case_dir <> "/post.ssz_snappy", BeaconState)

    slots_to_process =
      YamlElixir.read_from_file!(case_dir <> "/slots.yaml") |> SpecTestUtils.sanitize_yaml()

    assert is_integer(slots_to_process)

    case StateTransition.process_slots(pre, pre.slot + slots_to_process) do
      {:ok, state} ->
        assert Diff.diff(state, post) == :unchanged

      {:error, error} ->
        assert post == nil, "Process slots failed, error: #{error}"
    end
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{handler: "blocks"} = testcase) do
    # TODO process meta.yaml
    Helpers.ProcessBlocks.process_blocks(testcase)
  end
end
