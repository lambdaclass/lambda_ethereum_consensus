defmodule Unit.P2p.RequestsTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.P2p.Requests

  test "An empty requests object shouldn't handle a request" do
    requests = Requests.new()

    assert {:unhandled, requests} ==
             Requests.handle_response(requests, "some response", "fake id")
  end

  test "A requests object should handler a request only once" do
    requests = Requests.new()
    pid = self()

    {requests_2, handler_id} =
      Requests.add_response_handler(
        requests,
        fn response -> send(pid, response) end
      )

    {:ok, requests_3} = Requests.handle_response(requests_2, "some response", handler_id)

    response =
      receive do
        response -> response
      end

    assert response == "some response"

    assert requests_3 == requests

    assert {:unhandled, requests_3} ==
             Requests.handle_response(requests, "some response", handler_id)
  end
end
