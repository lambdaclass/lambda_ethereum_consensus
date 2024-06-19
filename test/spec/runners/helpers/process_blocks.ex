defmodule Helpers.ProcessBlocks do
  @moduledoc """
  Helper module for processing blocks.
  """

  use ExUnit.CaseTemplate

  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.Utils.Diff
 alias LambdaEthereumConsensus.Types.Base.BeaconState
 alias LambdaEthereumConsensus.Types.Base.BlockInfo
 alias LambdaEthereumConsensus.Types.Base.SignedBeaconBlock

  def process_blocks(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    pre = SpecTestUtils.read_ssz_from_file!(case_dir <> "/pre.ssz_snappy", BeaconState)
    post = SpecTestUtils.read_ssz_from_optional_file!(case_dir <> "/post.ssz_snappy", BeaconState)

    meta = YamlElixir.read_from_file!(case_dir <> "/meta.yaml") |> SpecTestUtils.sanitize_yaml()

    %{blocks_count: blocks_count} = meta

    blocks =
      0..(blocks_count - 1)//1
      |> Enum.map(fn index ->
        SpecTestUtils.read_ssz_from_file!(
          case_dir <> "/blocks_#{index}.ssz_snappy",
          SignedBeaconBlock
        )
      end)

    result =
      blocks
      |> Enum.reduce_while({:ok, pre}, fn block, {:ok, state} ->
        case StateTransition.verified_transition(state, BlockInfo.from_block(block)) do
          {:ok, post_state} -> {:cont, {:ok, post_state.beacon_state}}
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
