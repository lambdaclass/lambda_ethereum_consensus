defmodule LambdaEthereumConsensus.Store.KvSchema do
  @moduledoc """
  Utilities to define modules that auto-generate get, put and delete methods, according
  to a specification. Every schema needs some specs:
  - How to encode/decode values.
  - How to encode/decode keys (if not binary already).
  - What the prefix for the schema is, so it doesn't collide with others.
  """

  alias LambdaEthereumConsensus.Store.Db

  @type encode_result :: {:ok, binary()} | {:error, binary()}
  @type decode_result :: {:ok, term()} | {:error, binary()}

  @callback encode_key(term()) :: encode_result()
  @callback decode_key(term()) :: decode_result()
  @callback encode_value(term()) :: encode_result()
  @callback decode_value(term()) :: decode_result()

  defmacro __using__(prefix: prefix) do
    quote do
      # These types are just for documentation reasons.
      @type key :: term()
      @type value :: term()
      @type acc :: term()

      @prefix unquote(prefix)
      @behaviour LambdaEthereumConsensus.Store.KvSchema

      @spec get(key()) :: {:ok, value()} | {:error, binary()} | :not_found
      def get(key) do
        db_span("get", fn ->
          with {:ok, encoded_key} <- encode_key(key),
               {:ok, encoded_value} <- Db.get(@prefix <> encoded_key) do
            decode_value(encoded_value)
          end
        end)
      end

      @spec put(key(), value()) :: :ok | {:error, binary()}
      def put(key, value) do
        db_span("put", fn ->
          with {:ok, encoded_key} <- encode_key(key),
               {:ok, encoded_value} <- encode_value(value) do
            Db.put(@prefix <> encoded_key, encoded_value)
          end
        end)
      end

      @spec delete(key()) :: :ok | {:error, binary()}
      def delete(key) do
        db_span("delete", fn ->
          with {:ok, encoded_key} <- encode_key(key) do
            Db.delete(@prefix <> encoded_key)
          end
        end)
      end

      @spec fold(key(), acc(), (key(), acc() -> acc())) :: acc()
      def fold(start_key, starting_value, f) do
        db_span("fold", fn ->
          with {:ok, it} <- Db.iterate(),
               {:ok, encoded_start} <- encode_key(start_key),
               {:ok, @prefix <> _, _} <- Exleveldb.iterator_move(it, encoded_start) do
            res = iterate(it, starting_value, f)
            Exleveldb.iterator_close(it)
            {:ok, res}
          end
        end)
      end

      defp iterate(it, acc, f) do
        case Exleveldb.iterator_move(it, :prev) do
          # TODO: add option to get the value in the function too if needed.
          {:ok, @prefix <> k, v} -> iterate(it, f.(decode_key(k), acc), f)
          _ -> acc
        end
      end

      defp db_span(action, f) do
        :telemetry.span([:db, :latency], %{}, fn -> {f.(), %{module: @prefix, action: action}} end)
      end
    end
  end
end
