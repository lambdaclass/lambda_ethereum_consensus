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
    # "ComplexTestStruct",
    # "BitsStruct"
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
         expected_hash_tree_root
       ) do
    real_struct = struct!(module, parse_complex_container(real_deserialized, module))
    {:ok, deserialized} = SszEx.decode(real_serialized, module)

    assert deserialized == real_struct
    {:ok, serialized} = SszEx.encode(real_struct, module)

    assert serialized == real_serialized
    actual_hash_tree_root = SszEx.hash_tree_root!(real_struct, module)
    assert actual_hash_tree_root == expected_hash_tree_root
  end

  defp assert_ssz(
         "valid",
         {:vector, _basic_type, _size} = schema,
         real_serialized,
         real_deserialized,
         expected_hash_tree_root
       ) do
    {:ok, deserialized} = SszEx.decode(real_serialized, schema)
    assert deserialized == real_deserialized

    {:ok, serialized} = SszEx.encode(real_deserialized, schema)

    assert serialized == real_serialized

    actual_hash_tree_root = SszEx.hash_tree_root!(real_deserialized, schema)

    assert actual_hash_tree_root == expected_hash_tree_root
  end

  defp assert_ssz(
         "valid",
         {:bitlist, _size} = schema,
         real_serialized,
         real_deserialized,
         _expected_hash_tree_root
       ) do
    {:ok, deserialized_value} = SszEx.decode(real_deserialized, schema)
    serialized_result = BitList.to_bytes({deserialized_value, bit_size(deserialized_value)})
    assert real_serialized == serialized_result

    {:ok, deserialized} = SszEx.decode(real_serialized, schema)
    assert deserialized == deserialized_value

    # TODO merkleization of bitlist
    # {:ok, actual_hash_tree_root} = SszEx.hash_tree_root(real_deserialized, schema)
    #
    # assert actual_hash_tree_root == expected_hash_tree_root
  end

  defp assert_ssz(
         "valid",
         {:bitvector, _size} = schema,
         real_serialized,
         real_deserialized,
         _expected_hash_tree_root
       ) do
    {:ok, deserialized_value} = SszEx.decode(real_deserialized, schema)
    serialized_result = BitVector.to_bytes(deserialized_value)
    assert real_serialized == serialized_result

    {:ok, deserialized} = SszEx.decode(real_serialized, schema)
    assert deserialized == deserialized_value

    # TODO merkleization of bitlist
    # {:ok, actual_hash_tree_root} = SszEx.hash_tree_root(real_deserialized, schema)
    #
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

  defp assert_ssz(
         "invalid",
         {:container, module},
         real_serialized
       ) do
    assert {:error, _deserialized} = SszEx.decode(real_serialized, module)
  end

  defp assert_ssz("invalid", schema, real_serialized) do
    assert {:error, _msg} = SszEx.decode(real_serialized, schema)
  end

  defp get_vec_schema(rest) do
    case String.split(rest, "_") do
      ["bool", max_size | _] ->
        {:vector, :bool, String.to_integer(max_size)}

      ["uint" <> size, max_size | _] ->
        {:vector, {:int, String.to_integer(size)}, String.to_integer(max_size)}
    end
  end

  defp get_bit_list_schema(cse) do
    case cse do
      # Test format is inconsistent, pretend the limit is 32 (arbitrary)
      "bitlist_" <> "no" <> _rest ->
        {:bitlist, 32}

      "bitlist_" <> rest ->
        [size | _] = String.split(rest, "_")
        {:bitlist, String.to_integer(size)}
    end
  end

  def get_bit_vector_schema(cse) do
    case cse do
      "bitvec_" <> rest ->
        [size | _] = String.split(rest, "_")
        {:bitvector, String.to_integer(size)}
    end
  end

  defp parse_complex_container(value, module)
       when module == Helpers.SszStaticContainers.BitsStruct do
    value
    |> Enum.map(fn {key, value} ->
      case key do
        :A ->
          {:ok, deserialized_value} = SszEx.decode(value, {:bitlist, 5})
          {key, deserialized_value}

        :B ->
          {:ok, deserialized_value} = SszEx.decode(value, {:bitvector, 2})
          {key, deserialized_value}

        :C ->
          {:ok, deserialized_value} = SszEx.decode(value, {:bitvector, 1})
          {key, deserialized_value}

        :D ->
          {:ok, deserialized_value} = SszEx.decode(value, {:bitlist, 6})
          {key, deserialized_value}

        :E ->
          {:ok, deserialized_value} = SszEx.decode(value, {:bitvector, 8})
          {key, deserialized_value}
      end
    end)
  end

  defp parse_complex_container(value, module)
       when module == Helpers.SszStaticContainers.ComplexTestStruct do
    value
    |> Enum.map(fn {key, value} ->
      case key do
        :A ->
          {key, value}

        :B ->
          {key, value}

        :C ->
          {key, value}

        :D when is_integer(value) ->
          {key, []}

        :D ->
          {key, :binary.bin_to_list(value)}

        :E ->
          {key, struct!(Helpers.SszStaticContainers.VarTestStruct, value)}

        :F ->
          {key,
           Enum.map(value, fn v -> struct!(Helpers.SszStaticContainers.FixedTestStruct, v) end)}

        :G ->
          {key,
           Enum.map(value, fn v -> struct!(Helpers.SszStaticContainers.VarTestStruct, v) end)}
      end
    end)
  end

  defp parse_complex_container(value, _module), do: value

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

      "basic_vector" ->
        case cse do
          "vec_" <> rest ->
            get_vec_schema(rest)
        end

      "bitlist" ->
        get_bit_list_schema(cse)

      "bitvector" ->
        get_bit_vector_schema(cse)
    end
  end
end
