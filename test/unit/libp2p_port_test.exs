defmodule Unit.Libp2pPortTest do
  use ExUnit.Case
  use Patch

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Libp2pPort

  doctest Libp2pPort

  setup do
    patch(BeaconChain, :get_fork_version, fn -> ChainSpec.get("CAPELLA_FORK_VERSION") end)
    :ok
  end

  defp start_port(name \\ Libp2pPort, init_args \\ []) do
    start_link_supervised!({Libp2pPort, [opts: [name: name]] ++ init_args}, id: name)
  end

  test "start port", do: start_port()

  test "start multiple ports" do
    start_port()
    start_port(:host1)
    start_port(:host2)
    start_port(:host3)
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

  test "start discovery service and discover one peer" do
    bootnodes = YamlElixir.read_from_file!("config/networks/mainnet/boot_enr.yaml")

    start_port(:discoverer,
      enable_discovery: true,
      discovery_addr: "0.0.0.0:25101",
      bootnodes: bootnodes,
      new_peer_handler: self()
    )

    assert_receive {:new_peer, _peer_id}, 10_000
  end

  defp two_hosts_gossip do
    gossiper_addr = ["/ip4/127.0.0.1/tcp/48766"]
    start_port(:publisher)
    start_port(:gossiper, listen_addr: gossiper_addr)

    topic = "/test/gossipping"
    message = "hello world!"

    # Connect the two peers
    id = Libp2pPort.get_id(:gossiper)
    :ok = Libp2pPort.add_peer(:publisher, id, gossiper_addr, 999_999_999_999)

    pid = self()

    spawn_link(fn ->
      # Subscribe to the topic
      :ok = Libp2pPort.subscribe_to_topic(:gossiper, topic)
      send(pid, :subscribed)

      # Receive the message
      assert {^topic, message_id, ^message} = Libp2pPort.receive_gossip()

      Libp2pPort.validate_message(message_id, :accept)

      # Send acknowledgement
      send(pid, :received)
    end)

    # Give a head start to the other process
    assert_receive :subscribed, 100

    # Publish message
    :ok = Libp2pPort.publish(:publisher, topic, message)

    # Receive acknowledgement
    assert_receive :received, 100
  end

  defp retry_test(f, retries) do
    f.()
  rescue
    ExUnit.AssertionError ->
      assert retries > 0, "Retry limit exceeded"
      stop_supervised(:publisher)
      stop_supervised(:gossiper)
      retry_test(f, retries - 1)
  end

  test "start two hosts, and gossip about" do
    retry_test(&two_hosts_gossip/0, 5)
  end
end
