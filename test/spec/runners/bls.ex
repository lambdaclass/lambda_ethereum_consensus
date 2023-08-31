defmodule BLSTestRunner do
  use ExUnit.CaseTemplate

  @moduledoc """
  Runner for BLS test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/bls
  """

  # Remove handler from here once you implement the corresponding functions
  @disabled_handlers [
    "sign",
    "verify",
    "aggregate",
    "fast_aggregate_verify",
    "aggregate_verify",
    "eth_aggregate_pubkeys",
    "eth_fast_aggregate_verify"
  ]

  @doc """
  Returns true if the given testcase should be skipped
  """
  def skip?(%SpecTestCase{} = testcase) do
    Enum.member?(@disabled_handlers, testcase.handler)
  end

  @doc """
  Runs the given test case.
  """
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    %{input: input, output: output} =
      YamlElixir.read_from_file!(case_dir <> "/data.yaml")
      |> SpecTestUtils.parse_yaml()

    case testcase.handler do
      "sign" ->
        assert_sign(input, output)

      "verify" ->
        assert_verify(input, output)

      "aggregate" ->
        assert_aggregate(input, output)

      "fast_aggregate_verify" ->
        assert_fast_aggregate_verify(input, output)

      "aggregate_verify" ->
        assert_aggregate_verify(input, output)

      "eth_aggregate_pubkeys" ->
        assert_eth_aggregate_pubkeys(input, output)

      "eth_fast_aggregate_verify" ->
        assert_eth_fast_aggregate_verify(input, output)

      handler ->
        raise "Unknown case: #{handler}"
    end
  end

  defp assert_sign(_input, _output) do
    assert false
  end

  defp assert_aggregate(_input, _output) do
    assert false
  end

  defp assert_fast_aggregate_verify(_input, _output) do
    assert false
  end

  defp assert_aggregate_verify(_input, _output) do
    assert false
  end

  defp assert_verify(_input, _output) do
    assert false
  end

  def assert_eth_aggregate_pubkeys(_input, _output) do
    assert false
  end

  def assert_eth_fast_aggregate_verify(_input, _output) do
    assert false
  end
end
