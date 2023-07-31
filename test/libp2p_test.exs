defmodule Libp2pTest do
  use ExUnit.Case
  doctest Libp2p

  test "greets the world" do
    assert Libp2p.hello() == :world
  end

  test "my_function is a + 2 * b" do
    assert Libp2p.my_function(5, 124) == 5 + 2 * 124
  end

  test "test_send_message sends a message" do
    :ok = Libp2p.test_send_message()

    receive do
      msg -> {:ok, 5353} = msg
    after
      1_000 -> :timeout
    end
  end

  test "Create and destroy host" do
    {:ok, host} = Libp2p.host_new()
    assert host != 0
    :ok = Libp2p.host_close(host)
  end

  test "Set stream handler" do
    {:ok, host} = Libp2p.host_new()
    assert host != 0
    :ok = Libp2p.host_set_stream_handler(host, "/my-app/amazing-protocol/1.0.1")
    :ok = Libp2p.host_close(host)
  end

  test "Start two hosts, and play one round of ping-pong" do
    # Setup sender
    {:ok, sender} = Libp2p.host_new()
    # Setup receiver
    {:ok, recver} = Libp2p.host_new()

    :ok = Libp2p.host_set_stream_handler(recver, "/pong")

    :ok = Libp2p.host_close(host1)
    :ok = Libp2p.host_close(host2)
  end
end
