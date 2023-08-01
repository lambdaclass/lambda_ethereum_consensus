defmodule Libp2pTest do
  use ExUnit.Case
  doctest Libp2p

  test "Create and destroy host" do
    {:ok, host} = Libp2p.host_new()
    assert host != 0
    Libp2p.host_close(host)
  end

  test "Set stream handler" do
    {:ok, host} = Libp2p.host_new()
    assert host != 0
    :ok = Libp2p.host_set_stream_handler(host, ~c"/my-app/amazing-protocol/1.0.1")
    Libp2p.host_close(host)
  end

  test "Start two hosts, and play one round of ping-pong" do
    # Setup sender
    {:ok, sender} = Libp2p.host_new()
    # Setup receiver
    {:ok, recver} = Libp2p.host_new()

    # (recver) Set stream handler
    :ok = Libp2p.host_set_stream_handler(recver, ~c"/pong")

    # (sender) Add recver address to peerstore
    {:ok, peerstore} = Libp2p.host_peerstore(sender)
    {:ok, id} = Libp2p.host_id(recver)
    {:ok, addrs} = Libp2p.host_addrs(recver)

    Libp2p.peerstore_add_addrs(peerstore, id, addrs, Libp2p.ttl_permanent_addr())

    # (sender) Create stream sender -> recver
    {:ok, send} = Libp2p.host_new_stream(sender, id, ~c"/pong")

    # (sender) Write "ping" to stream
    :ok = Libp2p.stream_write(send, ~c"ping")

    # (recver) Receive the stream via the configured stream handler
    {:ok, recv} =
      receive do
        msg -> msg
      after
        5_000 -> :timeout
      end

    # (recver) Read the "ping" message from the stream
    {:ok, ~c"ping"} = Libp2p.stream_read(recv)

    # (recver) Write "pong" to the stream
    :ok = Libp2p.stream_write(recv, ~c"pong")

    # (sender) Read the "pong" message from the stream
    {:ok, ~c"pong"} = Libp2p.stream_read(send)

    # Close both streams
    Libp2p.stream_close(send)
    Libp2p.stream_close(recv)

    # Close both hosts
    Libp2p.host_close(sender)
    Libp2p.host_close(recver)
  end
end
