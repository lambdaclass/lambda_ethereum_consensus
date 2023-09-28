defmodule Unit.Libp2pTest do
  use ExUnit.Case
  doctest Libp2p

  test "Create and destroy host" do
    {:ok, host} = Libp2p.host_new()
    assert host != 0
    :ok = Libp2p.host_close(host)
  end

  test "Use peerstore in place of host fails" do
    {:ok, host} = Libp2p.host_new()
    {:ok, peerstore} = Libp2p.host_peerstore(host)
    {:error, "invalid Host"} = Libp2p.host_close(peerstore)
    :ok = Libp2p.host_close(host)
  end

  test "Set stream handler" do
    {:ok, host} = Libp2p.host_new()
    assert host != 0
    :ok = Libp2p.host_set_stream_handler(host, "/my-app/amazing-protocol/1.0.1")
    :ok = Libp2p.host_close(host)
  end

  test "listen_addr_strings parsing" do
    {:ok, option} = Libp2p.listen_addr_strings("/ip4/127.0.0.1/tcp/48787")
    assert option != 0
  end

  test "Start two hosts, and play one round of ping-pong" do
    # Setup sender
    {:ok, addr} = Libp2p.listen_addr_strings("/ip4/127.0.0.1/tcp/48787")
    {:ok, sender} = Libp2p.host_new([addr])
    # Setup receiver
    {:ok, addr} = Libp2p.listen_addr_strings("/ip4/127.0.0.1/tcp/48789")
    {:ok, recver} = Libp2p.host_new([addr])

    protocol_id = "/pong"

    # (recver) Set stream handler
    :ok = Libp2p.host_set_stream_handler(recver, protocol_id)

    # (sender) Add recver address to peerstore
    {:ok, peerstore} = Libp2p.host_peerstore(sender)
    {:ok, id} = Libp2p.host_id(recver)
    {:ok, addrs} = Libp2p.host_addrs(recver)

    :ok = Libp2p.peerstore_add_addrs(peerstore, id, addrs, Libp2p.ttl_permanent_addr())

    # (sender) Create stream sender -> recver
    {:ok, send} = Libp2p.host_new_stream(sender, id, protocol_id)

    # (sender) Write "ping" to stream
    :ok = Libp2p.stream_write(send, "ping")
    :ok = Libp2p.stream_close_write(send)

    # (recver) Receive the stream via the configured stream handler
    {:ok, recv} =
      receive do
        {:req, msg} -> msg
      after
        1000 -> :timeout
      end

    # (recver) Read the "ping" message from the stream
    {:ok, "ping"} = Libp2p.stream_read(recv)
    {:ok, ""} = Libp2p.stream_read(recv)

    # (recver) Write "pong" to the stream
    :ok = Libp2p.stream_write(recv, "pong")
    :ok = Libp2p.stream_close_write(recv)

    # (sender) Read the "pong" message from the stream
    {:ok, "pong"} = Libp2p.stream_read(send)

    :ok = Libp2p.stream_close(send)
    :ok = Libp2p.stream_close(recv)

    # Close both hosts
    :ok = Libp2p.host_close(sender)
    :ok = Libp2p.host_close(recver)
  end

  defp retrying_receive(topic_sender, msg) do
    # (sender) Give a head start to the other process
    Process.sleep(1)

    # (sender) Publish a message to the topic
    :ok = Libp2p.topic_publish(topic_sender, msg)

    receive do
      :ok -> :ok
    after
      20 -> retrying_receive(topic_sender, msg)
    end
  end

  test "start two hosts, and gossip about" do
    # Setup sender
    {:ok, addr} = Libp2p.listen_addr_strings("/ip4/127.0.0.1/tcp/48787")
    {:ok, sender} = Libp2p.host_new([addr])
    # Setup receiver
    {:ok, addr} = Libp2p.listen_addr_strings("/ip4/127.0.0.1/tcp/48789")
    {:ok, recver} = Libp2p.host_new([addr])

    # (sender) Connect to recver
    {:ok, peerstore} = Libp2p.host_peerstore(sender)
    {:ok, id} = Libp2p.host_id(recver)
    {:ok, addrs} = Libp2p.host_addrs(recver)

    :ok = Libp2p.peerstore_add_addrs(peerstore, id, addrs, Libp2p.ttl_permanent_addr())
    :ok = Libp2p.host_connect(sender, id)

    # Create GossipSubs
    {:ok, gsub_sender} = Libp2p.new_gossip_sub(sender)
    {:ok, gsub_recver} = Libp2p.new_gossip_sub(recver)

    topic = "/test/gossipping"

    # Join the topic
    {:ok, topic_sender} = Libp2p.pub_sub_join(gsub_sender, topic)
    {:ok, topic_recver} = Libp2p.pub_sub_join(gsub_recver, topic)

    pid = self()
    msg = "hello world!"

    spawn_link(fn ->
      # (recver) Subscribe to the topic
      {:ok, sub_recver} = Libp2p.topic_subscribe(topic_recver)

      assert {:ok, message} = Libp2p.next_subscription_message()

      Libp2p.subscription_cancel(sub_recver)

      # Subscription returns error before cancelling
      assert :cancelled = Libp2p.next_subscription_message()

      # (recver) Get the application data from the message
      {:ok, data} = Libp2p.message_data(message)

      assert data == msg
      send(pid, :ok)
    end)

    retrying_receive(topic_sender, msg)

    # Close both hosts
    :ok = Libp2p.host_close(sender)
    :ok = Libp2p.host_close(recver)
  end
end
