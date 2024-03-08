defmodule ForkChoiceTestRunner do
  @moduledoc """
  Runner for Fork Choice test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/fork_choice
  """

  use ExUnit.CaseTemplate
  use TestRunner

  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.ForkChoice.Helpers
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.SignedBeaconBlock
  alias Types.Store

  use HardForkAliasInjection

  @disabled_on_block_cases [
    # "basic",
    # "incompatible_justification_update_end_of_epoch",
    # "incompatible_justification_update_start_of_epoch",
    # "justification_update_beginning_of_epoch",
    # "justification_update_end_of_epoch",
    # "justification_withholding",
    # "justification_withholding_reverse_order",
    # "justified_update_always_if_better",
    # "justified_update_monotonic",
    # "justified_update_not_realized_finality",
    # "new_finalized_slot_is_justified_checkpoint_ancestor",
    # "not_pull_up_current_epoch_block",
    # "on_block_bad_parent_root",
    # "on_block_before_finalized",
    # "on_block_checkpoints",
    # "on_block_finalized_skip_slots",
    # "on_block_finalized_skip_slots_not_in_skip_chain",
    # "on_block_future_block",
    # "proposer_boost",
    # "proposer_boost_root_same_slot_untimely_block",
    # "pull_up_on_tick",
    # "pull_up_past_epoch_block"
  ]

  @disabled_ex_ante_cases [
    # "ex_ante_attestations_is_greater_than_proposer_boost_with_boost",
    # "ex_ante_sandwich_with_boost_not_sufficient",
    # "ex_ante_sandwich_with_honest_attestation",
    # "ex_ante_sandwich_without_attestations",
    # "ex_ante_vanilla"
  ]

  @disabled_get_head_cases [
    # "chain_no_attestations",
    # "discard_equivocations_on_attester_slashing",
    # "discard_equivocations_slashed_validator_censoring",
    # "filtered_block_tree",
    # "genesis",
    # "proposer_boost_correct_head",
    # "shorter_chain_but_heavier_weight",
    # "split_tie_breaker_no_attestations",
    # "voting_source_beyond_two_epoch",
    # "voting_source_within_two_epoch"
  ]

  @disabled_reorg_cases [
    # "delayed_justification_current_epoch",
    # "delayed_justification_previous_epoch",
    # "include_votes_another_empty_chain_with_enough_ffg_votes_current_epoch",
    # "include_votes_another_empty_chain_with_enough_ffg_votes_previous_epoch",
    # "include_votes_another_empty_chain_without_enough_ffg_votes_current_epoch",
    # "simple_attempted_reorg_delayed_justification_current_epoch",
    # "simple_attempted_reorg_delayed_justification_previous_epoch",
    # "simple_attempted_reorg_without_enough_ffg_votes"
  ]

  @disabled_withholding_cases [
    # "withholding_attack",
    # "withholding_attack_unviable_honest_chain"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: "capella", case: testcase}) do
    Enum.member?(@disabled_on_block_cases, testcase) or
      Enum.member?(@disabled_ex_ante_cases, testcase) or
      Enum.member?(@disabled_get_head_cases, testcase) or
      Enum.member?(@disabled_reorg_cases, testcase) or
      Enum.member?(@disabled_withholding_cases, testcase)
  end

  def skip?(_testcase), do: true

  @impl TestRunner
  def run_test_case(testcase) do
    assert false
    case_dir = SpecTestCase.dir(testcase)

    anchor_state =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/anchor_state.ssz_snappy",
        Types.BeaconState
      )

    anchor_block =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/anchor_block.ssz_snappy",
        Types.BeaconBlock
      )

    steps =
      YamlElixir.read_from_file!(case_dir <> "/steps.yaml") |> SpecTestUtils.sanitize_yaml()

    signed_block = %SignedBeaconBlock{message: anchor_block, signature: <<0::768>>}

    {:ok, store} = Store.get_forkchoice_store(anchor_state, signed_block)

    assert {:ok, _store} = apply_steps(case_dir, store, steps)
  end

  @spec apply_steps(String.t(), Store.t(), list()) ::
          {:ok, Store.t()} | {:error, binary()}
  defp apply_steps(case_dir, store, steps) do
    Enum.reduce_while(steps, {:ok, store}, fn step, {:ok, %Store{} = store} ->
      should_be_valid = Map.get(step, :valid, true)

      case {apply_step(case_dir, store, step), should_be_valid} do
        {{:ok, new_store}, true} ->
          {:cont, {:ok, new_store}}

        {{:ok, _store}, false} ->
          {:halt, {:error, "expected invalid step to fail"}}

        {{:error, error}, true} ->
          {:halt, {:error, error}}

        {{:error, _error}, false} ->
          {:halt, {:ok, store}}
      end
    end)
  end

  @spec apply_step(String.t(), Store.t(), map()) ::
          {:ok, Store.t()} | {:error, binary()}
  defp apply_step(case_dir, store, step)

  defp apply_step(_case_dir, store, %{tick: time}) do
    new_store = Handlers.on_tick(store, time)
    {:ok, new_store}
  end

  defp apply_step(case_dir, store, %{block: "block_0x" <> hash = file}) do
    block =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/#{file}.ssz_snappy",
        Types.SignedBeaconBlock
      )

    assert Ssz.hash_tree_root!(block) == Base.decode16!(hash, case: :mixed)

    with {:ok, new_store} <- Handlers.on_block(store, block),
         {:ok, new_store} <-
           block.message.body.attestations
           |> Enum.reduce_while({:ok, new_store}, fn
             x, {:ok, st} -> {:cont, Handlers.on_attestation(st, x, true)}
             _, {:error, _} = err -> {:halt, err}
           end) do
      {:ok, head_root} = Helpers.get_head(new_store)
      head_block = Blocks.get_block!(head_root)

      {:ok, _} = Handlers.notify_forkchoice_update(new_store, head_block)
      {:ok, new_store}
    end
  end

  defp apply_step(case_dir, store, %{attestation: "attestation_0x" <> hash = file}) do
    attestation =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/#{file}.ssz_snappy",
        Types.Attestation
      )

    assert Ssz.hash_tree_root!(attestation) == Base.decode16!(hash, case: :mixed)
    Handlers.on_attestation(store, attestation, false)
  end

  defp apply_step(case_dir, store, %{attester_slashing: "attester_slashing_0x" <> hash = file}) do
    attester_slashing =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/#{file}.ssz_snappy",
        Types.AttesterSlashing
      )

    assert Ssz.hash_tree_root!(attester_slashing) == Base.decode16!(hash, case: :mixed)
    Handlers.on_attester_slashing(store, attester_slashing)
  end

  defp apply_step(_case_dir, store, %{block_hash: block_hash, payload_status: payload_status}) do
    # Convert keys to strings
    normalized_payload_status =
      Enum.reduce(payload_status, %{}, fn {k, v}, acc ->
        Map.put(acc, Atom.to_string(k), v)
      end)

    :ok =
      SyncTestRunner.EngineApiMock.add_new_payload_response(
        block_hash,
        normalized_payload_status
      )

    :ok =
      SyncTestRunner.EngineApiMock.add_forkchoice_updated_response(
        block_hash,
        normalized_payload_status
      )

    {:ok, store}
  end

  defp apply_step(_case_dir, store, %{checks: checks}) do
    if Map.has_key?(checks, :head) do
      {:ok, head_root} = Helpers.get_head(store)
      assert head_root == checks.head.root
      assert Blocks.get_block!(head_root).slot == checks.head.slot
    end

    if Map.has_key?(checks, :time) do
      assert store.time == checks.time
    end

    if Map.has_key?(checks, :justified_checkpoint) do
      assert store.justified_checkpoint.epoch == checks.justified_checkpoint.epoch
      assert store.justified_checkpoint.root == checks.justified_checkpoint.root
    end

    if Map.has_key?(checks, :finalized_checkpoint) do
      assert store.finalized_checkpoint.epoch == checks.finalized_checkpoint.epoch
      assert store.finalized_checkpoint.root == checks.finalized_checkpoint.root
    end

    if Map.has_key?(checks, :proposer_boost_root) do
      assert store.proposer_boost_root == checks.proposer_boost_root
    end

    {:ok, store}
  end
end
