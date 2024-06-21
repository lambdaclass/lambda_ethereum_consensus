defmodule Unit.Store.KvSchemaTest do
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.KvSchema
  use ExUnit.Case

  defmodule TupleSchema do
    @moduledoc """
    Schema with tuples as keys and lists as value, using erlang native encoding for both keys
    and values.

    The prefix begins with a letter "a" to guarantee that it's stored before the number schema.
    """
    use KvSchema, prefix: "a_tuple_schema"

    @impl KvSchema
    def encode_key({_a, _b} = t), do: {:ok, :erlang.term_to_binary(t)}

    @impl KvSchema
    def decode_key(b), do: {:ok, :erlang.binary_to_term(b)}

    @impl KvSchema
    def encode_value(l) when is_list(l), do: {:ok, :erlang.term_to_binary(l)}

    @impl KvSchema
    def decode_value(b), do: {:ok, :erlang.binary_to_term(b)}
  end

  defmodule NumberSchema do
    @moduledoc """
    Schema with numbers as keys and dictionaries as values. Uses erlang native encoding for
    values, but string encoding for keys.
    """
    use KvSchema, prefix: "number_schema"

    @impl KvSchema
    def encode_key(n) when is_integer(n), do: {:ok, inspect(n)}

    @impl KvSchema
    def decode_key(b) do
      case Integer.parse(b) do
        {n, ""} when is_integer(n) -> {:ok, n}
        other -> {:error, "could not parse: #{other}"}
      end
    end

    @impl KvSchema
    def encode_value(m) when is_map(m), do: {:ok, :erlang.term_to_binary(m)}

    @impl KvSchema
    def decode_value(b) do
      case :erlang.binary_to_term(b) do
        m when is_map(m) -> {:ok, m}
        other -> {:error, "Error decoding value, #{inspect(other)} is not a map."}
      end
    end
  end

  setup %{tmp_dir: tmp_dir} do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.put(:config, MinimalConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))

    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    :ok
  end

  @tag :tmp_dir
  test "Putting, getting, deleting work" do
    assert :not_found = TupleSchema.get({:a, :b})
    assert :ok = TupleSchema.put({:a, :b}, [1, 2, 3])
    assert {:ok, [1, 2, 3]} == TupleSchema.get({:a, :b})
    assert :not_found = TupleSchema.get({:a, :c})
    assert :ok = TupleSchema.delete({:a, :b})
    assert :not_found = TupleSchema.get({:a, :b})

    assert :not_found = NumberSchema.get(1)
    assert :ok = NumberSchema.put(1, %{"some_key" => "some_value"})
    assert {:ok, %{"some_key" => "some_value"}} == NumberSchema.get(1)
    assert :not_found = NumberSchema.get(2)
    assert :ok = NumberSchema.delete(1)
    assert :not_found = NumberSchema.get(1)
  end

  @tag :tmp_dir
  test "An error is yielded when decoding fails" do
    Db.put("number_schema2", :erlang.term_to_binary(%{"a" => "b"}))
    assert {:ok, %{"a" => "b"}} == NumberSchema.get(2)

    Db.put("number_schema2", :erlang.term_to_binary([1, 2, 3]))
    {:error, "Error decoding value, [1, 2, 3] is not a map."} = NumberSchema.get(2)
  end

  @tag :tmp_dir
  test "Folding stops if there is a different schema" do
    TupleSchema.put({1, 2}, [])
    NumberSchema.put(1, %{"a" => "b"})
    NumberSchema.put(2, %{b: 3})
    NumberSchema.put(70, %{c: 5})

    assert {:ok, 3} == NumberSchema.fold(70, 0, fn n, acc -> acc + n end)
  end
end
