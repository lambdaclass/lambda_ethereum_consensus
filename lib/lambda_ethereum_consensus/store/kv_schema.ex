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

  defmacro __using__(_params) do
    quote do
      @behaviour LambdaEthereumConsensus.Store.KvSchema

      @spec get(term()) :: {:ok, term()} | {:error, binary()} | :not_found
      def get(key) do
        with {:ok, encoded_key} <- encode_key(key),
             {:ok, encoded_value} <- Db.get(encoded_key) do
          decode_value(encoded_value)
        end
      end

      @spec put(term(), term()) :: :ok | {:error, binary()}
      def put(key, value) do
        with {:ok, encoded_key} <- encode_key(key),
             {:ok, encoded_value} <- encode_value(value) do
          Db.put(encoded_key, encoded_value)
        end
      end

      @spec delete(term()) :: :ok | {:error, binary()}
      def delete(key) do
        with {:ok, encoded_key} <- encode_key(key) do
          Db.delete(encoded_key)
        end
      end
    end
  end
end
