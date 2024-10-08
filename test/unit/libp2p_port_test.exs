defmodule Unit.Libp2pPortTest do
  use ExUnit.Case
  use Patch

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip.Handler
  alias LambdaEthereumConsensus.P2P.Metadata
  alias LambdaEthereumConsensus.P2P.ReqResp
  alias Types.Store

  doctest Libp2pPort

  setup %{tmp_dir: tmp_dir} do
    patch(ForkChoice, :get_fork_version, fn -> ChainSpec.get("DENEB_FORK_VERSION") end)
    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    :ok
  end

  defp start_port(name \\ Libp2pPort, init_args \\ []) do
    start_link_supervised!(
      {Libp2pPort,
       [opts: [name: name], store: %Store{}, genesis_time: :os.system_time(:second)] ++ init_args},
      id: name
    )
  end

  @tag :tmp_dir
  test "start port", do: start_port()

  @tag :tmp_dir
  test "start multiple ports" do
    start_port()
    start_port(:host1)
    start_port(:host2)
    start_port(:host3)
  end

  @tag :tmp_dir
  test "start two hosts, and play one round of ping-pong" do
    # Setup sender
    start_port(:sender, listen_addr: ["/ip4/127.0.0.1/tcp/48787"])

    # Setup receiver
    recver_addr = ["/ip4/127.0.0.1/tcp/48789"]
    start_port(:recver, listen_addr: recver_addr, enable_request_handlers: true)

    # Setup request
    %{peer_id: id} = Libp2pPort.get_node_identity(:recver)
    protocol_id = "/eth2/beacon_chain/req/ping/1/ssz_snappy"
    message = ReqResp.encode_request({2, TypeAliases.uint64()})

    # Setup expected result
    expected_seq_num = 1
    patch(Metadata, :get_seq_number, fn -> expected_seq_num end)
    expected_result = {:ok, ReqResp.encode_ok({expected_seq_num, TypeAliases.uint64()})}

    # (sender) Add recver peer
    :ok = Libp2pPort.add_peer(:sender, id, recver_addr, 999_999_999_999)

    # (sender) Send "ping" to recver
    assert expected_result ==
             Libp2pPort.send_request(:sender, id, protocol_id, message)
  end

  # TODO: flaky test, fix
  @tag :skip
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

  @tag :tmp_dir
  defp two_hosts_gossip() do
    gossiper_addr = ["/ip4/127.0.0.1/tcp/48766"]
    start_port(:publisher)
    start_port(:gossiper, listen_addr: gossiper_addr)

    # Send the PID in the message, so that we can receive a notification later.
    message = self() |> :erlang.term_to_binary()
    topic = "/test/gossipping"

    # Connect the two peers
    %{peer_id: id} = Libp2pPort.get_node_identity(:gossiper)
    :ok = Libp2pPort.add_peer(:publisher, id, gossiper_addr, 999_999_999_999)

    # Subscribe to the topic
    :ok = Libp2pPort.subscribe_to_topic(:gossiper, topic, __MODULE__)

    # Publish message
    :ok = Libp2pPort.publish(:publisher, topic, message)

    # Receive the message
    assert {^topic, message_id, ^message} = Libp2pPort.receive_gossip()

    Libp2pPort.validate_message(message_id, :accept)
  end

  @behaviour Handler
  def handle_gossip_message(_store, topic, msg_id, message) do
    # Decode the PID from the message and send a notification.
    send(:erlang.binary_to_term(message), {:gossipsub, {topic, msg_id, message}})
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

  @tag :tmp_dir
  test "start two hosts, and gossip about" do
    retry_test(&two_hosts_gossip/0, 5)
  end

  @tag :tmp_dir
  test "subscribe, leave, and join topic" do
    port = start_port(:some, listen_addr: ["/ip4/127.0.0.1/tcp/48790"])
    topic = "test"

    Libp2pPort.subscribe_to_topic(port, topic, __MODULE__)
    Libp2pPort.leave_topic(port, topic)
    Libp2pPort.join_topic(port, topic)
  end

  @tag :tmp_dir
  test "get node identity" do
    addr = "/ip4/127.0.0.1/tcp/48795"

    port =
      start_port(:some,
        listen_addr: [addr],
        enable_discovery: true,
        discovery_addr: "localhost:48796"
      )

    identity = Libp2pPort.get_node_identity(port)

    assert %{pretty_peer_id: peer_id, peer_id: _peer_id, enr: enr} = identity

    assert String.printable?(peer_id)
    assert String.starts_with?(enr, "enr:")

    assert %{p2p_addresses: [p2p_address], discovery_addresses: [discovery_address]} = identity
    assert p2p_address == addr <> "/p2p/" <> peer_id
    assert discovery_address == "/ip4/127.0.0.1/udp/48796" <> "/p2p/" <> peer_id
  end
end
