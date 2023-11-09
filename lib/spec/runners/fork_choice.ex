defmodule ForkChoiceTestRunner do
  @moduledoc """
  Runner for Fork Choice test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/fork_choice
  """

  use ExUnit.CaseTemplate
  use TestRunner

  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.ForkChoice.Helpers
  alias SszTypes.Store

  @disabled_handlers [
    "on_block",
    "ex_ante",
    "get_head",
    "reorg",
    "withholding"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: fork, handler: handler, case: _testcase}) do
    fork != "capella" or Enum.member?(@disabled_handlers, handler)
  end

  @impl TestRunner
  def run_test_case(testcase) do
    case_dir = SpecTestCase.dir(testcase)

    anchor_state =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/anchor_state.ssz_snappy",
        SszTypes.BeaconState
      )

    anchor_block =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/anchor_block.ssz_snappy",
        SszTypes.BeaconBlock
      )

    steps =
      YamlElixir.read_from_file!(case_dir <> "/steps.yaml") |> SpecTestUtils.sanitize_yaml()

    {:ok, store} = Helpers.get_forkchoice_store(anchor_state, anchor_block)

    result = apply_steps(case_dir, store, steps)

    case result do
      %Store{} = _store ->
        assert true

      {:error, error} ->
        assert false, error
    end
  end

  @spec apply_steps(String.t(), Store.t(), list()) ::
          Store.t() | {:error, binary()}
  defp apply_steps(case_dir, store, steps) do
    Enum.reduce_while(steps, store, fn step, %Store{} = store ->
      should_be_valid = Map.get(step, "valid", true)

      case {apply_step(case_dir, store, step), should_be_valid} do
        {{:ok, new_store}, true} ->
          {:cont, new_store}

        {{:ok, _store}, false} ->
          {:halt, {:error, "expected invalid step to fail"}}

        {{:error, error}, true} ->
          {:halt, {:error, error}}

        {{:error, _error}, false} ->
          {:halt, store}
      end
    end)
  end

  @spec apply_step(Store.t(), Store.t(), map()) ::
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
        SszTypes.SignedBeaconBlock
      )

    assert Ssz.hash_tree_root!(block.message) == Base.decode16!(hash, case: :mixed)
    Handlers.on_block(store, block)
  end

  defp apply_step(case_dir, store, %{attestation: "attestation_0x" <> hash = file}) do
    attestation =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/#{file}.ssz_snappy",
        SszTypes.Attestation
      )

    assert Ssz.hash_tree_root!(attestation) == Base.decode16!(hash, case: :mixed)
    Handlers.on_attestation(store, attestation, false)
  end

  defp apply_step(case_dir, store, %{attester_slashing: "attester_slashing_0x" <> hash = file}) do
    attester_slashing =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/#{file}.ssz_snappy",
        SszTypes.AttesterSlashing
      )

    assert Ssz.hash_tree_root!(attester_slashing) == Base.decode16!(hash, case: :mixed)
    Handlers.on_attester_slashing(store, attester_slashing)
  end

  defp apply_step(_case_dir, store, %{checks: checks}) do
    if %{head: %{root: root, slot: slot}} = checks do
      {:ok, head_root} = Helpers.get_head(store)
      assert head_root == root
      assert store.blocks[head_root].slot == slot
    end

    if %{time: time} = checks do
      assert store.time == time
    end

    if %{justified_checkpoint: justified_checkpoint} = checks do
      assert store.justified_checkpoint.epoch == justified_checkpoint.epoch
      assert store.justified_checkpoint.root == justified_checkpoint.root
    end

    if %{finalized_checkpoint: finalized_checkpoint} = checks do
      assert store.finalized_checkpoint.epoch == finalized_checkpoint.epoch
      assert store.finalized_checkpoint.root == finalized_checkpoint.root
    end

    if %{proposer_boost_root: proposer_boost_root} = checks do
      assert store.proposer_boost_root == proposer_boost_root
    end

    {:ok, store}
  end

  defp apply_step(_, _, _) do
    {:error, "unknown step"}
  end
end
