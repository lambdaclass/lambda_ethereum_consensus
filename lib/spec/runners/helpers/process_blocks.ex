defmodule Helpers.ProcessBlocks do
  @moduledoc """
  Helper module for processing blocks.
  """

  use ExUnit.CaseTemplate

  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.Utils.Diff

  def process_blocks(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    pre =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/pre.ssz_snappy",
        SszTypes.BeaconState
      )

    post =
      SpecTestUtils.read_ssz_from_optional_file!(
        case_dir <> "/post.ssz_snappy",
        SszTypes.BeaconState
      )

    meta =
      YamlElixir.read_from_file!(case_dir <> "/meta.yaml") |> SpecTestUtils.sanitize_yaml()

    dbg(meta)

    %{blocks_count: blocks_count} = meta

    blocks =
      0..(blocks_count - 1)//1
      |> Enum.map(fn index ->
        SpecTestUtils.read_ssz_from_file!(
          case_dir <> "/blocks_#{index}.ssz_snappy",
          SszTypes.SignedBeaconBlock
        )
      end)

    result =
      blocks
      |> Enum.reduce_while({:ok, pre}, fn block, {:ok, state} ->
        case StateTransition.state_transition(state, block, true) do
          {:ok, post_state} -> {:cont, {:ok, post_state}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    case result do
      {:ok, state} ->
        assert Diff.diff(state, post) == :unchanged

      {:error, error} ->
        assert post == nil, "Process block failed, error: #{error}"
    end
  end
end
