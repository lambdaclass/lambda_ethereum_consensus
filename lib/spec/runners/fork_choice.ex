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

  @enabled_cases [
    "genesis"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: fork, handler: handler, case: testcase}) do
    (fork != "capella" or Enum.member?(@disabled_handlers, handler)) and
      not Enum.member?(@enabled_cases, testcase)
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

    assert {:ok, _store} = apply_steps(case_dir, store, steps)
  end

  @spec apply_steps(String.t(), Store.t(), list()) ::
          Store.t() | {:error, binary()}
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
        SszTypes.SignedBeaconBlock
      )

    assert Ssz.hash_tree_root!(block) == Base.decode16!(hash, case: :mixed)

    with {:ok, new_store} <- Handlers.on_block(store, block) do
      block.message.body.attestations
      |> Enum.reduce_while({:ok, new_store}, fn
        x, {:ok, st} -> {:cont, Handlers.on_attestation(st, x, true)}
        _, {:error, _} = err -> {:halt, err}
      end)
    end
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
    if Map.has_key?(checks, :head) do
      {:ok, head_root} = Helpers.get_head(store)
      assert head_root == checks.head.root
      assert store.blocks[head_root].slot == checks.head.slot
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

  defp apply_step(_, _, _) do
    {:error, "unknown step"}
  end
end
