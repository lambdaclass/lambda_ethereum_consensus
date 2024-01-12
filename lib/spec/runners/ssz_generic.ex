defmodule SszGenericTestRunner do
  @moduledoc """
  Runner for SSZ general test cases. `run_test_case/1` is the main entrypoint.
  """
  alias LambdaEthereumConsensus.SszEx
  use ExUnit.CaseTemplate
  use TestRunner

  @disabled [
    # "basic_vector",
    "bitlist",
    "bitvector"
    # "boolean",
    # "containers"
    # "uints"
  ]

  @disabled_containers [
    # "SingleFieldTestStruct",
    # "SmallTestStruct",
    # "FixedTestStruct",
    # "VarTestStruct",
    "ComplexTestStruct",
    "BitsStruct"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: fork, handler: handler, case: cse}) do
    skip_container? =
      @disabled_containers
      |> Enum.map(fn container -> String.contains?(cse, container) end)
      |> Enum.any?()

    fork != "phase0" or Enum.member?(@disabled, handler) or skip_container?
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    schema = parse_type(testcase)

    compressed = File.read!(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, decompressed} = :snappyer.decompress(compressed)

    handle_case(testcase.suite, schema, decompressed, testcase)
  end

  defp handle_case("valid", schema, real_serialized, testcase) do
    case_dir = SpecTestCase.dir(testcase)

    expected_value =
      YamlElixir.read_from_file!(case_dir <> "/value.yaml")
      |> SpecTestUtils.sanitize_yaml()

    %{root: expected_root} =
      YamlElixir.read_from_file!(case_dir <> "/meta.yaml")
      |> SpecTestUtils.sanitize_yaml()

    assert_ssz("valid", schema, real_serialized, expected_value, expected_root)
  end

  defp handle_case("invalid", schema, real_serialized, _testcase) do
    assert_ssz("invalid", schema, real_serialized)
  end

  defp assert_ssz(
         "valid",
         {:container, module},
         real_serialized,
         real_deserialized,
         _hash_tree_root
       ) do
    real_struct = struct!(module, real_deserialized)
    {:ok, deserialized} = SszEx.decode(real_serialized, module)
    assert deserialized == real_struct
    {:ok, serialized} = SszEx.encode(real_struct, module)
    assert serialized == real_serialized
  end

  defp assert_ssz(
         "valid",
         {:vector, _basic_type, _size} = schema,
         real_serialized,
         real_deserialized,
         _expected_hash_tree_root
       ) do
    {:ok, deserialized} = SszEx.decode(real_serialized, schema)
    assert deserialized == real_deserialized

    {:ok, serialized} = SszEx.encode(real_deserialized, schema)

    assert serialized == real_serialized

    # actual_hash_tree_root = SszEx.hash_tree_root!(real_deserialized, schema)

    # assert actual_hash_tree_root == expected_hash_tree_root
  end

  defp assert_ssz("valid", schema, real_serialized, real_deserialized, expected_hash_tree_root) do
    {:ok, deserialized} = SszEx.decode(real_serialized, schema)
    assert deserialized == real_deserialized

    {:ok, serialized} = SszEx.encode(real_deserialized, schema)

    assert serialized == real_serialized

    actual_hash_tree_root = SszEx.hash_tree_root!(real_deserialized, schema)

    assert actual_hash_tree_root == expected_hash_tree_root
  end

  defp assert_ssz("invalid", schema, real_serialized) do
    catch_error(SszEx.encode(real_serialized, schema))
  end

  defp get_vec_schema(rest) do
    case String.split(rest, "_") do
      ["bool", max_size | _] ->
        {:vector, :bool, String.to_integer(max_size)}

      ["uint" <> size, max_size | _] ->
        {:vector, {:int, String.to_integer(size)}, String.to_integer(max_size)}
    end
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
        end

      "containers" ->
        [name] = Regex.run(~r/^[^_]+(?=_)/, cse)
        {:container, Module.concat(Helpers.SszStaticContainers, name)}

      # TODO enable when basic_vector and bitlist tests are enable
      "basic_vector" ->
        case cse do
          "vec_" <> rest ->
            get_vec_schema(rest)
        end

        #
        # "bitlist" ->
        #   case cse do
        #     "bitlist_" <> rest ->
        #       [size | _] = String.split(rest, "_")
        #       {:bitlist, String.to_integer(size)}
        #   end
    end
  end
end
