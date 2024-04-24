defmodule ForkChoiceTestRunner do
  @moduledoc """
  Runner for Fork Choice test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/fork_choice
  """

  use ExUnit.CaseTemplate
  use TestRunner

  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.ForkChoice.Helpers
  alias LambdaEthereumConsensus.Store.BlobDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.BeaconBlock
  alias Types.BeaconState
  alias Types.SignedBeaconBlock
  alias Types.Store

  @impl TestRunner
  def skip?(%SpecTestCase{fork: "capella"}), do: false
  def skip?(%SpecTestCase{fork: "deneb"}), do: false
  def skip?(_testcase), do: true

  @impl TestRunner
  def run_test_case(testcase) do
    case_dir = SpecTestCase.dir(testcase)

    anchor_state =
      SpecTestUtils.read_ssz_from_file!(case_dir <> "/anchor_state.ssz_snappy", BeaconState)

    anchor_block =
      SpecTestUtils.read_ssz_from_file!(case_dir <> "/anchor_block.ssz_snappy", BeaconBlock)

    steps = YamlElixir.read_from_file!(case_dir <> "/steps.yaml") |> SpecTestUtils.sanitize_yaml()

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

  defp apply_step(case_dir, store, %{block: "block_0x" <> hash = file} = step) do
    block =
      SpecTestUtils.read_ssz_from_file!(case_dir <> "/#{file}.ssz_snappy", SignedBeaconBlock)

    assert Ssz.hash_tree_root!(block) == Base.decode16!(hash, case: :mixed)

    load_blob_data(case_dir, block, step)

    with {:ok, new_store} <- Handlers.on_block(store, block),
         {:ok, new_store} <-
           block.message.body.attestations
           |> Enum.reduce_while({:ok, new_store}, fn
             x, {:ok, st} -> {:cont, Handlers.on_attestation(st, x, true)}
             _, {:error, _} = err -> {:halt, err}
           end) do
      {:ok, head_root} = Helpers.get_head(new_store)
      head_block = Blocks.get_block!(head_root)

      {:ok, _result} = Handlers.notify_forkchoice_update(new_store, head_block)
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

  # TODO: validate the filename's hash
  defp load_blob_data(case_dir, block, %{blobs: "blobs_0x" <> _hash = blobs_file, proofs: proofs}) do
    schema = {:list, TypeAliases.blob(), ChainSpec.get("MAX_BLOBS_PER_BLOCK")}

    blobs = SpecTestUtils.read_ssz_ex_from_file!(case_dir <> "/#{blobs_file}.ssz_snappy", schema)

    block_root = Ssz.hash_tree_root!(block.message)

    Stream.zip([proofs, blobs])
    |> Stream.with_index()
    |> Enum.each(fn {{proof, blob}, i} ->
      BlobDb.store_blob_with_proof(block_root, i, blob, proof)
    end)
  end

  defp load_blob_data(_case_dir, block, %{}) do
    assert Enum.empty?(block.message.body.blob_kzg_commitments)
  end
end
