defmodule LambdaEthereumConsensus.P2p.Requests do
  @moduledoc """
  Uses uuids to identify requests and their handlers. Saves the handler in the struct until a
  response is available and then handles appropriately.
  """
  @type id :: binary
  @type handler :: (term() -> term())
  @type requests :: %{id => handler}

  @doc """
  Creates a requests object that will hold response handlers.
  """
  @spec new() :: requests()
  def new(), do: %{}

  @doc """
  Adds a handler for a request.

  Returns a tuple {requests, request_id}, where:
  - Requests is the modified requests object with the added handler.
  - The id for the handler for that request. This will be used later when calling handle_response/3.
  """
  @spec add_response_handler(requests(), handler()) :: {requests(), id()}
  def add_response_handler(requests, handler) do
    id = UUID.uuid4()
    {Map.put(requests, id, handler), id}
  end

  @doc """
  Handles a request using handler_id. The handler will be popped from the
  requests object.

  Returns a {status, requests} tuple where:
  - status is :ok if it was handled or :unhandled if the id didn't correspond to a saved handler.
  - requests is the modified requests object with the handler removed.
  """
  @spec handle_response(requests(), term(), id()) :: {:ok | :unhandled, requests()}
  def handle_response(requests, response, handler_id) do
    case Map.fetch(requests, handler_id) do
      {:ok, handler} ->
        handler.(response)
        {:ok, Map.delete(requests, handler_id)}

      :error ->
        {:unhandled, requests}
    end
  end
end
