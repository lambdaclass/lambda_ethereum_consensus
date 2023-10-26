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
  def skip?(%SpecTestCase{fork: fork, handler: handler, case: testcase}) do
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

    result = apply_steps(store, steps)

    case result do
      %Store{} = _store ->
        assert true

      {:error, error} ->
        assert false, error

      _ ->
        assert false, "result is not a store: #{inspect(result)}"
    end
  end

  @spec apply_steps(ForkChoiceStore.t(), list()) ::
          ForkChoiceStore.t() | {:error, binary()}
  defp apply_steps(store, steps) do
    Enum.reduce_while(steps, store, fn step, %Store{} = store ->
      should_be_valid = Map.get(step, "valid", true)

      case {apply_step(store, step), should_be_valid} do
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

  @spec apply_step(ForkChoiceStore.t(), map()) ::
          {:ok, ForkChoiceStore.t()} | {:error, binary()}
  defp apply_step(store, step)

  defp apply_step(store, %{tick: time}) do
    Handlers.on_tick(store, time)
  end

  defp apply_step(store, %{checks: checks}) do
    if Map.has_key?(checks, :head) do
      {:ok, head_root} = Helpers.get_head(store)
      assert head_root == checks.head.root
      # TODO get block and assert the slot
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

  defp apply_step(store, %{block: block}) do
    Handlers.on_block(store, block)
  end
end
