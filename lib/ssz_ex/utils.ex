defmodule SszEx.Utils do
  @moduledoc """
  Utilities for SszEx.
  """

  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Utils.BitVector
  alias SszEx.Error

  @allowed_uints [8, 16, 32, 64, 128, 256]
  @bits_per_byte 8
  @bytes_per_boolean 4

  @spec validate_schema!(SszEx.schema()) :: :ok
  def validate_schema!(:bool), do: :ok
  def validate_schema!({:int, n}) when n in @allowed_uints, do: :ok
  def validate_schema!({:byte_list, size}) when size > 0, do: :ok
  def validate_schema!({:byte_vector, size}) when size > 0, do: :ok
  def validate_schema!({:list, sub, size}) when size > 0, do: validate_schema!(sub)
  def validate_schema!({:vector, sub, size}) when size > 0, do: validate_schema!(sub)
  def validate_schema!({:bitlist, size}) when size > 0, do: :ok
  def validate_schema!({:bitvector, size}) when size > 0, do: :ok

  def validate_schema!(module) when is_atom(module) do
    schema = module.schema()
    # validate each sub-schema
    {fields, subschemas} = Enum.unzip(schema)
    Enum.each(subschemas, &validate_schema!/1)

    # check the struct field names match the schema keys
    struct_fields =
      module.__struct__() |> Map.keys() |> MapSet.new() |> MapSet.delete(:__struct__)

    fields = MapSet.new(fields)

    if MapSet.equal?(fields, struct_fields) do
      :ok
    else
      missing =
        MapSet.symmetric_difference(fields, struct_fields)
        |> Enum.map_join(", ", &inspect/1)

      raise "The struct and its schema differ by some fields: #{missing}"
    end
  end

  @doc """
  Returns the default value for a schema, which can be a basic or composite type.
  """
  def default({:int, _}), do: 0
  def default(:bool), do: false
  def default({:byte_list, _size}), do: <<>>
  def default({:byte_vector, size}), do: <<0::size(size * 8)>>
  def default({:list, _, _}), do: []
  def default({:vector, inner_type, size}), do: default(inner_type) |> List.duplicate(size)
  def default({:bitlist, _}), do: BitList.default()
  def default({:bitvector, size}), do: BitVector.new(size)

  def default(module) when is_atom(module) do
    module.schema()
    |> Enum.map(fn {attr, schema} -> {attr, default(schema)} end)
    |> then(&struct!(module, &1))
  end

  def flatten_results(results) do
    flatten_results_by(results, &Function.identity/1)
  end

  def flatten_results_by(results, fun) do
    case Enum.group_by(results, fn {type, _} -> type end, fn {_, result} -> result end) do
      %{error: [first_error | _rest]} -> {:error, first_error}
      summary -> {:ok, fun.(Map.get(summary, :ok, []))}
    end
  end

  def get_fixed_size(:bool), do: 1
  def get_fixed_size({:int, size}), do: div(size, @bits_per_byte)
  def get_fixed_size({:byte_vector, size}), do: size
  def get_fixed_size({:vector, inner_type, size}), do: size * get_fixed_size(inner_type)
  def get_fixed_size({:bitvector, size}), do: div(size + 7, 8)

  def get_fixed_size(module) when is_atom(module) do
    schemas = module.schema()

    schemas
    |> Enum.map(fn {_, schema} -> get_fixed_size(schema) end)
    |> Enum.sum()
  end

  def variable_size?({:list, _, _}), do: true
  def variable_size?(:bool), do: false
  def variable_size?({:byte_list, _}), do: true
  def variable_size?({:byte_vector, _}), do: false
  def variable_size?({:int, _}), do: false
  def variable_size?({:bitlist, _}), do: true
  def variable_size?({:bitvector, _}), do: false
  def variable_size?({:vector, inner_type, _}), do: variable_size?(inner_type)

  def variable_size?(module) when is_atom(module) do
    module.schema()
    |> Enum.map(fn {_, schema} -> variable_size?(schema) end)
    |> Enum.any?()
  end

  def basic_type?({:int, _}), do: true
  def basic_type?(:bool), do: true
  def basic_type?({:list, _, _}), do: false
  def basic_type?({:vector, _, _}), do: false
  def basic_type?({:bitlist, _}), do: false
  def basic_type?({:bitvector, _}), do: false
  def basic_type?({:byte_list, _}), do: false
  def basic_type?({:byte_vector, _}), do: false
  def basic_type?(module) when is_atom(module), do: false

  def size_of(:bool), do: @bytes_per_boolean

  def size_of({:int, size}), do: size |> div(@bits_per_byte)

  def add_trace({:error, %Error{} = error}, module),
    do: {:error, Error.add_trace(error, module)}

  def add_trace(value, _module), do: value
end
