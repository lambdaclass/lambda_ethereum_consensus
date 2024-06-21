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
          with {:ok, encoded_key} <- do_encode_key(key),
               {:ok, encoded_value} <- Db.get(encoded_key) do
            do_decode_value(encoded_value)
          end
        end)
      end

      @spec put(key(), value()) :: :ok | {:error, binary()}
      def put(key, value) do
        db_span("put", fn ->
          with {:ok, encoded_key} <- do_encode_key(key),
               {:ok, encoded_value} <- do_encode_value(value) do
            Db.put(encoded_key, encoded_value)
          end
        end)
      end

      @spec delete(key()) :: :ok | {:error, binary()}
      def delete(key) do
        db_span("delete", fn ->
          with {:ok, encoded_key} <- do_encode_key(key) do
            Db.delete(encoded_key)
          end
        end)
      end

      @spec fold(key(), acc(), (key(), acc() -> acc())) :: {:ok, acc()} | {:error, binary()}
      def fold(start_key, starting_value, f) do
        db_span("fold", fn ->
          with {:ok, it} <- Db.iterate(),
               {:ok, encoded_start} <- do_encode_key(start_key),
               {:ok, ^encoded_start, _} <- Exleveldb.iterator_move(it, encoded_start) do
            res = iterate(it, starting_value, f)
            Exleveldb.iterator_close(it)
            {:ok, res}
          else
            # Failed at moving the iterator for the first time.
            {:ok, some_key, _some_value} ->
              {:error,
               "Failed to start iterator for table #{@prefix}. The obtained key is: #{some_key}"}

            other ->
              other
          end
        end)
      end

      defp iterate(it, acc, f) do
        case Exleveldb.iterator_move(it, :prev) do
          # TODO: add option to get the value in the function too if needed.
          {:ok, @prefix <> _ = k, v} ->
            # TODO: plan for weird corner cases where the key can't be decoded.
            {:ok, decoded_key} = do_decode_key(k)
            iterate(it, f.(decoded_key, acc), f)

          _ ->
            acc
        end
      end

      defp db_span(action, f) do
        :telemetry.span([:db, :latency], %{}, fn -> {f.(), %{module: @prefix, action: action}} end)
      end

      # Encodes the key with the prefix, and measures the time it takes.
      defp do_encode_key(key) do
        db_span("encode_key", fn ->
          with {:ok, encoded_key} <- encode_key(key) do
            {:ok, @prefix <> encoded_key}
          end
        end)
      end

      # Decodes the key with the prefix, and measures the time it takes.
      defp do_decode_key(key) do
        db_span("decode_key", fn ->
          @prefix <> no_prefix_key = key
          decode_key(no_prefix_key)
        end)
      end

      defp do_encode_value(value), do: db_span("encode_value", fn -> encode_value(value) end)
      defp do_decode_value(value), do: db_span("decode_value", fn -> decode_value(value) end)
    end
  end
end
