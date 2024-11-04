# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks
# TODO #1236: fix the credo check.
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

      @spec fold_keys(key(), acc(), (key(), acc() -> acc())) :: {:ok, acc()} | {:error, any()}
      def fold_keys(start_key, starting_value, f, opts \\ []) do
        db_span("fold_keys", fn ->
          include_first? = Keyword.get(opts, :include_first, false)
          direction = Keyword.get(opts, :direction, :prev)

          with {:ok, it} <- Db.iterate_keys(),
               {:ok, encoded_start} <- do_encode_key(start_key),
               {:ok, ^encoded_start} <- Db.iterator_move(it, encoded_start) do
            res = iterate(it, starting_value, f, direction, encoded_start, include_first?)
            Db.iterator_close(it)
            {:ok, res}
          else
            # The iterator moved for the first time to a place where it wasn't expected.
            {:ok, some_key} ->
              {:error,
               "Failed to start iterator for table #{@prefix}. The obtained key is: #{some_key}"}

            other ->
              other
          end
        end)
      end

      @doc """
      Returns all keys for a schema. Will be an empty list if no keys are found for the schema
      in the db.
      """
      def all_keys() do
        db_span("all_keys", fn -> stream_all_keys() |> Enum.to_list() end)
      end

      @doc """
      Stream all keys for the kv schema, starting from the first one and going in the
      :next direction.
      """
      def stream_all_keys() do
        case first_key() do
          {:ok, key} -> stream_keys(key, :next)
          :not_found -> []
        end
      end

      @doc """
      Returns the first key of the schema, or :not_found if no elements of the schema are present
      in the db.
      """
      @spec first_key() :: {:ok, key()} | :not_found
      def first_key() do
        {:ok, it} = Db.iterate_keys()

        case Db.iterator_move(it, @prefix) do
          {:ok, @prefix <> _k = full_key} -> do_decode_key(full_key)
          {:ok, _other} -> :not_found
          {:error, :invalid_iterator} -> :not_found
        end
      end

      @doc """
      Returns an elixir Stream for the KvSchema, that can be used with the Stream or Enum libraries
      for general purpose iteration.
      """
      def stream_keys(start_key, direction) do
        Stream.resource(
          fn -> key_iterator(start_key) end,
          &next_key(&1, direction),
          &close/1
        )
      end

      # NOTE: Exleveldb iterator_move returns the key when found. If it doesn't find the exact key,
      # it returns the first available key that's lexicographically higher than the one  requested.
      # That's why we match against {:ok, some_key} as a failure to initialize an iterator. In the
      # case where no higher key is available, iterator_move returns {:error, :invalid_iterator}.
      defp key_iterator(key) do
        with {:ok, it} <- Db.iterate_keys(),
             {:ok, encoded_start} <- do_encode_key(key),
             {:ok, ^encoded_start} <- Db.iterator_move(it, encoded_start) do
          {:first, it, key}
        else
          # The iterator moved for the first time to a place where it wasn't expected.
          {:ok, some_key} ->
            {:error,
             "Failed to start iterator for table #{@prefix}. The obtained key is: #{some_key}"}

          other ->
            other
        end
      end

      defp next_key({:next, it}, direction), do: move_iterator(it, direction)

      # The first iteration is just returning the first key.
      defp next_key({:first, it, key}, direction), do: {[key], {:next, it}}

      defp move_iterator(it, direction) do
        case Db.iterator_move(it, direction) do
          {:ok, @prefix <> _ = k} ->
            {:ok, decoded_key} = do_decode_key(k)
            {[decoded_key], {:next, it}}

          _ ->
            {:halt, it}
        end
      end

      # For the case when the iterator is never found, for any reason.
      defp next_key({:error, _}, _direction), do: nil

      defp close(nil), do: :ok
      defp close(it), do: :ok == Db.iterator_close(it)

      defp iterate(it, acc, f, direction, _first_key, false) do
        iterate(it, acc, f, direction)
      end

      defp iterate(it, acc, f, direction, first_key, true) do
        case accumulate(it, acc, f, first_key) do
          {:cont, new_acc} -> iterate(it, new_acc, f, direction)
          {:halt, new_acc} -> new_acc
        end
      end

      defp iterate(it, acc, f, direction) do
        case accumulate(it, acc, f, direction) do
          {:cont, acc} -> iterate(it, acc, f, direction)
          {:halt, acc} -> acc
        end
      end

      defp accumulate(it, acc, f, direction) do
        case Db.iterator_move(it, direction) do
          {:ok, @prefix <> _ = k} ->
            {:ok, decoded_key} = do_decode_key(k)
            {:cont, f.(decoded_key, acc)}

          _ ->
            {:halt, acc}
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
