defmodule SszGenericTestRunner do
  @moduledoc """
  Runner for SSZ general test cases. `run_test_case/1` is the main entrypoint.
  """
  alias LambdaEthereumConsensus.SszEx
  use ExUnit.CaseTemplate
  use TestRunner

  @disabled [
    "basic_vector",
    "bitlist",
    "bitvector",
    # "boolean",
    "containers"
    # "uints"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: fork, handler: handler}) do
    fork != "phase0" or Enum.member?(@disabled, handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    schema = parse_type(testcase)

    compressed = File.read!(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, decompressed} = :snappyer.decompress(compressed)

    handle_case(testcase.suite, schema, decompressed, testcase)
  end

  defp handle_case("valid", schema, real_deserialized, testcase) do
    case_dir = SpecTestCase.dir(testcase)

    expected =
      YamlElixir.read_from_file!(case_dir <> "/value.yaml")
      |> SpecTestUtils.sanitize_yaml()

    assert_ssz("valid", schema, real_deserialized, expected)
  end

  defp handle_case("invalid", schema, real_deserialized, _testcase) do
    assert_ssz("invalid", schema, real_deserialized)
  end

  defp assert_ssz("valid", schema, real_serialized, real_deserialized) do
    {:ok, deserialized} = SszEx.decode(real_serialized, schema)
    assert deserialized == real_deserialized

    {:ok, serialized} = SszEx.encode(real_deserialized, schema)

    assert serialized == real_serialized
  end

  defp assert_ssz("invalid", schema, real_serialized) do
    assert {:error, _error} = SszEx.encode(real_serialized, schema)
  end

  defp parse_type(%SpecTestCase{handler: handler, case: cse}) do
    case handler do
      "boolean" ->
        :bool

      "uints" ->
        case cse do
          "uint_" <> _rest ->
            [_head, size] = Regex.run(~r/^.*?_(.*?)_.*$/, cse)
            {:int, String.to_integer(size)}

          unknown ->
            :error
        end

      unknown ->
        :error
    end
  end
end
