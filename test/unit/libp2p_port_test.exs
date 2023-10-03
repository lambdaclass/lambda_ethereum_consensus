defmodule Unit.Libp2pPortTest do
  use ExUnit.Case
  alias LambdaEthereumConsensus.Libp2pPort

  doctest Libp2pPort

  defp start_port(name \\ Libp2pPort, init_args \\ []) do
    {:ok, pid} = Libp2pPort.start_link([opts: [name: name]] ++ init_args)
    assert Process.alive?(pid)
    # Kill process on exit
    on_exit(fn ->
      Process.unlink(pid)
      Process.exit(pid, :shutdown)
      refute Process.alive?(pid)
    end)
  end

  test "start port" do
    start_port(:host1)
  end

  test "set stream handler" do
    start_port()
    :ok = Libp2pPort.set_handler("/my-app/amazing-protocol/1.0.1")
  end

  test "start two hosts, and play one round of ping-pong" do
    # Setup sender
    start_port(:sender, listen_addr: ["/ip4/127.0.0.1/tcp/48787"])

    # Setup receiver
    recver_addr = ["/ip4/127.0.0.1/tcp/48789"]
    start_port(:recver, listen_addr: recver_addr)

    id = Libp2pPort.get_id(:recver)
    protocol_id = "/pong"
    pid = self()

    spawn_link(fn ->
      # (recver) Set stream handler
      :ok = Libp2pPort.set_handler(:recver, protocol_id)

      send(pid, :handler_set)

      # (recver) Read the "ping" message
      assert {^protocol_id, id, "ping"} = Libp2pPort.handle_request()
      :ok = Libp2pPort.send_response(:recver, id, "pong")

      send(pid, :message_received)
    end)

    # (sender) Wait for handler to be set
    assert_receive :handler_set, 1000

    # (sender) Add recver peer
    :ok = Libp2pPort.add_peer(:sender, id, recver_addr, 999_999_999_999)

    # (sender) Send "ping" to recver and receive "pong"
    assert {:ok, "pong"} = Libp2pPort.send_request(:sender, id, protocol_id, "ping")
    assert_receive :message_received, 1000
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

  @tag :skip
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
