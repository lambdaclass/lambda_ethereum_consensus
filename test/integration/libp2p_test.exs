defmodule Integration.Libp2pTest do
  use ExUnit.Case

  @bootnodes Application.compile_env(
               :lambda_ethereum_consensus,
               :discovery
             )[:bootnodes]

  @tag :skip
  test "discover peer and add it to peerstore" do
    {:ok, host} = Libp2p.host_new()

    {:ok, peerstore} = Libp2p.host_peerstore(host)

    {:ok, listener} =
      Libp2p.listen_v5("0.0.0.0:25000", @bootnodes)

    {:ok, iterator} = Libp2p.listener_random_nodes(listener)

    true = Libp2p.iterator_next(iterator)
    {:ok, node} = Libp2p.iterator_node(iterator)

    {:ok, id} = Libp2p.node_id(node)
    {:ok, addrs} = Libp2p.node_multiaddr(node)

    :ok = Libp2p.peerstore_add_addrs(peerstore, id, addrs, Libp2p.ttl_permanent_addr())

    :ok = Libp2p.host_close(host)
  end

  defp find_peers(host, iterator, fun) do
    {:ok, peerstore} = Libp2p.host_peerstore(host)

    true = Libp2p.iterator_next(iterator)

    {:ok, node} = Libp2p.iterator_node(iterator)

    if Libp2p.node_tcp(node) != nil do
      {:ok, id} = Libp2p.node_id(node)
      {:ok, addrs} = Libp2p.node_multiaddr(node)

      # 1 minute
      ttl = 6 * 10 ** 10
      :ok = Libp2p.peerstore_add_addrs(peerstore, id, addrs, ttl)

      fun.(id)
    end

    find_peers(host, iterator, fun)
  end

  defp receive_response(stream) do
    case Libp2p.stream_read(stream) do
      {:ok, msg} -> IO.puts(["\"#{Base.encode16(msg)}\""])
      _ -> :ok
    end
  end

  defp read_gossip_msg(sub) do
    receive do
      {:sub, {:ok, msg}} ->
        # NOTE: gossip messages are Snappy-compressed with BLOCK format (not frame)
        msg
        |> Libp2p.message_data()
        |> then(fn {:ok, d} -> d end)
        |> Base.encode16()
        |> then(&IO.puts(["\"#{&1}\""]))

      {:sub, {:error, err}} ->
        IO.puts(err)
    end

    read_gossip_msg(sub)
  end

  @tag :skip
  @tag timeout: :infinity
  test "discover new peers" do
    {:ok, host} = Libp2p.host_new()

    # ask for metadata
    protocol_id = "/eth2/beacon_chain/req/metadata/2/ssz_snappy"

    :ok = Libp2p.host_set_stream_handler(host, protocol_id)

    {:ok, listener} =
      Libp2p.listen_v5("0.0.0.0:45122", @bootnodes)

    {:ok, iterator} = Libp2p.listener_random_nodes(listener)

    find_peers(host, iterator, fn id ->
      with {:ok, stream} <- Libp2p.host_new_stream(host, id, protocol_id) do
        receive_response(stream)
      end
    end)

    :ok = Libp2p.host_close(host)
  end

  @tag :skip
  @tag timeout: :infinity
  test "ping peers" do
    {:ok, host} = Libp2p.host_new()

    # ping peers
    protocol_id = "/eth2/beacon_chain/req/ping/1/ssz_snappy"
    # uncompressed payload
    payload = Base.decode16!("0000000000000000")
    {:ok, compressed_payload} = Snappy.compress(payload)
    msg = <<8, compressed_payload::binary>>

    :ok = Libp2p.host_set_stream_handler(host, protocol_id)

    {:ok, listener} =
      Libp2p.listen_v5("0.0.0.0:45123", @bootnodes)

    {:ok, iterator} = Libp2p.listener_random_nodes(listener)

    find_peers(host, iterator, fn id ->
      with {:ok, stream} <- Libp2p.host_new_stream(host, id, protocol_id),
           :ok <- Libp2p.stream_write(stream, msg) do
        receive_response(stream)
      else
        {:error, err} -> IO.puts(err)
      end
    end)

    :ok = Libp2p.host_close(host)
  end

  @tag :skip
  @tag timeout: :infinity
  test "Gossip with CL peers" do
    # Setup host
    {:ok, host} = Libp2p.host_new()

    # Create GossipSubs
    {:ok, gsub} = Libp2p.new_gossip_sub(host)

    # Topic for Mainnet, Capella fork, attestation subnet 0
    topic_str = "/eth2/bba4da96/beacon_attestation_0/ssz_snappy"

    # Join the topic
    {:ok, topic} = Libp2p.pub_sub_join(gsub, topic_str)

    # Subscribe to the topic
    {:ok, sub} = Libp2p.topic_subscribe(topic)

    # Start discovery in another process
    {:ok, listener} = Libp2p.listen_v5("0.0.0.0:45124", @bootnodes)
    {:ok, iterator} = Libp2p.listener_random_nodes(listener)
    spawn(fn -> find_peers(host, iterator, &Libp2p.host_connect(host, &1)) end)

    # Read gossip messages
    read_gossip_msg(sub)

    :ok = Libp2p.host_close(host)
  end
end
