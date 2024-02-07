defmodule SszGenericTestRunner do
  @moduledoc """
  Runner for SSZ general test cases. `run_test_case/1` is the main entrypoint.
  """
  alias LambdaEthereumConsensus.SszEx
  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Utils.BitVector
  use ExUnit.CaseTemplate
  use TestRunner

  @disabled [
    # "basic_vector",
    # "bitlist",
    # "bitvector"
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
      |> sanitize(schema)

    %{root: expected_root} =
      YamlElixir.read_from_file!(case_dir <> "/meta.yaml")
      |> SpecTestUtils.sanitize_yaml()

    assert_ssz_valid(schema, real_serialized, expected_value, expected_root)
  end

  defp handle_case("invalid", schema, real_serialized, _testcase) do
    assert_ssz_invalid(schema, real_serialized)
  end

  defp assert_ssz_valid(schema, real_serialized, real_deserialized, expected_hash_tree_root) do
    {:ok, deserialized} = SszEx.decode(real_serialized, schema)
    assert deserialized == real_deserialized

    {:ok, serialized} = SszEx.encode(real_deserialized, schema)

    assert serialized == real_serialized

    ## TODO: To be removed when bitlist and bitvector is implemented
    case schema do
      {:bitlist, _} ->
        ## TODO
        nil

      {:bitvector, _} ->
        ## TODO
        nil

      _ ->
        actual_hash_tree_root = SszEx.hash_tree_root!(real_deserialized, schema)
        assert actual_hash_tree_root == expected_hash_tree_root
    end
  end

  defp assert_ssz_invalid(schema, real_serialized) do
    assert {:error, _msg} = SszEx.decode(real_serialized, schema)
  end

  defp parse_type(%SpecTestCase{handler: handler, case: cse}), do: parse_type(handler, cse)

  defp parse_type("boolean", _cse), do: :bool

  defp parse_type("uints", "uint_" <> rest) do
    [size | _] = String.split(rest, "_")
    {:int, String.to_integer(size)}
  end

  defp parse_type("containers", cse) do
    [name] = Regex.run(~r/^[^_]+(?=_)/, cse)
    Module.concat(Helpers.SszStaticContainers, name)
  end

  defp parse_type("basic_vector", "vec_" <> rest) do
    case String.split(rest, "_") do
      ["bool", max_size | _] ->
        {:vector, :bool, String.to_integer(max_size)}

      ["uint" <> size, max_size | _] ->
        {:vector, {:int, String.to_integer(size)}, String.to_integer(max_size)}
    end
  end

  # Test format is inconsistent, pretend the limit is 32 (arbitrary)
  defp parse_type("bitlist", "bitlist_" <> "no" <> _rest), do: {:bitlist, 32}

  defp parse_type("bitlist", "bitlist_" <> rest) do
    [size | _] = String.split(rest, "_")
    {:bitlist, String.to_integer(size)}
  end

  defp parse_type("bitvector", "bitvec_" <> rest) do
    [size | _] = String.split(rest, "_")
    {:bitvector, String.to_integer(size)}
  end

  def sanitize(container, module) when is_map(container) do
    schema = module.schema() |> Map.new()

    container
    |> Enum.map(fn {k, v} -> {k, sanitize(v, Map.fetch!(schema, k))} end)
    |> then(&struct!(module, &1))
  end

  def sanitize(vector_elements, {:vector, :bool, _size} = _schema), do: vector_elements

  def sanitize(vector_elements, {:vector, module, _size} = _schema) when is_atom(module),
    do:
      vector_elements
      |> Enum.map(&struct!(module, &1))

  def sanitize(bitlist, {:bitlist, _size} = _schema), do: elem(BitList.new(bitlist), 0)
  def sanitize(bitvector, {:bitvector, size} = _schema), do: BitVector.new(bitvector, size)

  def sanitize(bytelist, {:list, {:int, 8}, _size} = _schema)
      when is_integer(bytelist) and bytelist > 0,
      do: :binary.encode_unsigned(bytelist) |> :binary.bin_to_list()

  def sanitize(bytelist, {:list, {:int, 8}, _size} = _schema)
      when is_integer(bytelist) and bytelist == 0,
      do: []

  def sanitize(bytelist, {:list, {:int, 8}, _size} = _schema),
    do: :binary.bin_to_list(bytelist)

  def sanitize(other, _schema), do: other
end
