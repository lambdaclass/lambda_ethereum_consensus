defmodule Libp2pTest do
  use ExUnit.Case
  doctest Libp2p

  @bootnodes [
    "enr:-Le4QPUXJS2BTORXxyx2Ia-9ae4YqA_JWX3ssj4E_J-3z1A-HmFGrU8BpvpqhNabayXeOZ2Nq_sbeDgtzMJpLLnXFgAChGV0aDKQtTA_KgEAAAAAIgEAAAAAAIJpZIJ2NIJpcISsaa0Zg2lwNpAkAIkHAAAAAPA8kv_-awoTiXNlY3AyNTZrMaEDHAD2JKYevx89W0CcFJFiskdcEzkH_Wdv9iW42qLK79ODdWRwgiMohHVkcDaCI4I",
    "enr:-Le4QLHZDSvkLfqgEo8IWGG96h6mxwe_PsggC20CL3neLBjfXLGAQFOPSltZ7oP6ol54OvaNqO02Rnvb8YmDR274uq8ChGV0aDKQtTA_KgEAAAAAIgEAAAAAAIJpZIJ2NIJpcISLosQxg2lwNpAqAX4AAAAAAPA8kv_-ax65iXNlY3AyNTZrMaEDBJj7_dLFACaxBfaI8KZTh_SSJUjhyAyfshimvSqo22WDdWRwgiMohHVkcDaCI4I",
    "enr:-Le4QH6LQrusDbAHPjU_HcKOuMeXfdEB5NJyXgHWFadfHgiySqeDyusQMvfphdYWOzuSZO9Uq2AMRJR5O4ip7OvVma8BhGV0aDKQtTA_KgEAAAAAIgEAAAAAAIJpZIJ2NIJpcISLY9ncg2lwNpAkAh8AgQIBAAAAAAAAAAmXiXNlY3AyNTZrMaECDYCZTZEksF-kmgPholqgVt8IXr-8L7Nu7YrZ7HUpgxmDdWRwgiMohHVkcDaCI4I",
    "enr:-Le4QIqLuWybHNONr933Lk0dcMmAB5WgvGKRyDihy1wHDIVlNuuztX62W51voT4I8qD34GcTEOTmag1bcdZ_8aaT4NUBhGV0aDKQtTA_KgEAAAAAIgEAAAAAAIJpZIJ2NIJpcISLY04ng2lwNpAkAh8AgAIBAAAAAAAAAA-fiXNlY3AyNTZrMaEDscnRV6n1m-D9ID5UsURk0jsoKNXt1TIrj8uKOGW6iluDdWRwgiMohHVkcDaCI4I",
    "enr:-Ku4QHqVeJ8PPICcWk1vSn_XcSkjOkNiTg6Fmii5j6vUQgvzMc9L1goFnLKgXqBJspJjIsB91LTOleFmyWWrFVATGngBh2F0dG5ldHOIAAAAAAAAAACEZXRoMpC1MD8qAAAAAP__________gmlkgnY0gmlwhAMRHkWJc2VjcDI1NmsxoQKLVXFOhp2uX6jeT0DvvDpPcU8FWMjQdR4wMuORMhpX24N1ZHCCIyg",
    "enr:-Ku4QG-2_Md3sZIAUebGYT6g0SMskIml77l6yR-M_JXc-UdNHCmHQeOiMLbylPejyJsdAPsTHJyjJB2sYGDLe0dn8uYBh2F0dG5ldHOIAAAAAAAAAACEZXRoMpC1MD8qAAAAAP__________gmlkgnY0gmlwhBLY-NyJc2VjcDI1NmsxoQORcM6e19T1T9gi7jxEZjk_sjVLGFscUNqAY9obgZaxbIN1ZHCCIyg",
    "enr:-Ku4QPn5eVhcoF1opaFEvg1b6JNFD2rqVkHQ8HApOKK61OIcIXD127bKWgAtbwI7pnxx6cDyk_nI88TrZKQaGMZj0q0Bh2F0dG5ldHOIAAAAAAAAAACEZXRoMpC1MD8qAAAAAP__________gmlkgnY0gmlwhDayLMaJc2VjcDI1NmsxoQK2sBOLGcUb4AwuYzFuAVCaNHA-dy24UuEKkeFNgCVCsIN1ZHCCIyg",
    "enr:-Ku4QEWzdnVtXc2Q0ZVigfCGggOVB2Vc1ZCPEc6j21NIFLODSJbvNaef1g4PxhPwl_3kax86YPheFUSLXPRs98vvYsoBh2F0dG5ldHOIAAAAAAAAAACEZXRoMpC1MD8qAAAAAP__________gmlkgnY0gmlwhDZBrP2Jc2VjcDI1NmsxoQM6jr8Rb1ktLEsVcKAPa08wCsKUmvoQ8khiOl_SLozf9IN1ZHCCIyg",
    "enr:-KG4QOtcP9X1FbIMOe17QNMKqDxCpm14jcX5tiOE4_TyMrFqbmhPZHK_ZPG2Gxb1GE2xdtodOfx9-cgvNtxnRyHEmC0ghGV0aDKQ9aX9QgAAAAD__________4JpZIJ2NIJpcIQDE8KdiXNlY3AyNTZrMaEDhpehBDbZjM_L9ek699Y7vhUJ-eAdMyQW_Fil522Y0fODdGNwgiMog3VkcIIjKA",
    "enr:-KG4QDyytgmE4f7AnvW-ZaUOIi9i79qX4JwjRAiXBZCU65wOfBu-3Nb5I7b_Rmg3KCOcZM_C3y5pg7EBU5XGrcLTduQEhGV0aDKQ9aX9QgAAAAD__________4JpZIJ2NIJpcIQ2_DUbiXNlY3AyNTZrMaEDKnz_-ps3UUOfHWVYaskI5kWYO_vtYMGYCQRAR3gHDouDdGNwgiMog3VkcIIjKA",
    "enr:-Ku4QImhMc1z8yCiNJ1TyUxdcfNucje3BGwEHzodEZUan8PherEo4sF7pPHPSIB1NNuSg5fZy7qFsjmUKs2ea1Whi0EBh2F0dG5ldHOIAAAAAAAAAACEZXRoMpD1pf1CAAAAAP__________gmlkgnY0gmlwhBLf22SJc2VjcDI1NmsxoQOVphkDqal4QzPMksc5wnpuC3gvSC8AfbFOnZY_On34wIN1ZHCCIyg",
    "enr:-Ku4QP2xDnEtUXIjzJ_DhlCRN9SN99RYQPJL92TMlSv7U5C1YnYLjwOQHgZIUXw6c-BvRg2Yc2QsZxxoS_pPRVe0yK8Bh2F0dG5ldHOIAAAAAAAAAACEZXRoMpD1pf1CAAAAAP__________gmlkgnY0gmlwhBLf22SJc2VjcDI1NmsxoQMeFF5GrS7UZpAH2Ly84aLK-TyvH-dRo0JM1i8yygH50YN1ZHCCJxA",
    "enr:-Ku4QPp9z1W4tAO8Ber_NQierYaOStqhDqQdOPY3bB3jDgkjcbk6YrEnVYIiCBbTxuar3CzS528d2iE7TdJsrL-dEKoBh2F0dG5ldHOIAAAAAAAAAACEZXRoMpD1pf1CAAAAAP__________gmlkgnY0gmlwhBLf22SJc2VjcDI1NmsxoQMw5fqqkw2hHC4F5HZZDPsNmPdB1Gi8JPQK7pRc9XHh-oN1ZHCCKvg",
    "enr:-LK4QA8FfhaAjlb_BXsXxSfiysR7R52Nhi9JBt4F8SPssu8hdE1BXQQEtVDC3qStCW60LSO7hEsVHv5zm8_6Vnjhcn0Bh2F0dG5ldHOIAAAAAAAAAACEZXRoMpC1MD8qAAAAAP__________gmlkgnY0gmlwhAN4aBKJc2VjcDI1NmsxoQJerDhsJ-KxZ8sHySMOCmTO6sHM3iCFQ6VMvLTe948MyYN0Y3CCI4yDdWRwgiOM",
    "enr:-LK4QKWrXTpV9T78hNG6s8AM6IO4XH9kFT91uZtFg1GcsJ6dKovDOr1jtAAFPnS2lvNltkOGA9k29BUN7lFh_sjuc9QBh2F0dG5ldHOIAAAAAAAAAACEZXRoMpC1MD8qAAAAAP__________gmlkgnY0gmlwhANAdd-Jc2VjcDI1NmsxoQLQa6ai7y9PMN5hpLe5HmiJSlYzMuzP7ZhwRiwHvqNXdoN0Y3CCI4yDdWRwgiOM"
  ]

  def assert_snappy_decompress(compressed, uncompressed) do
    {:ok, ^uncompressed} =
      compressed
      |> Base.decode16!()
      |> Libp2p.snappy_decompress_stream()
  end

  test "Test snappy stream decompression" do
    # Uncompressed chunks
    msg = "0011FF060000734E6150705901150000F1D17CFF0008000000000000FFFFFFFFFFFFFFFF0F"
    # status <> length <> ...
    "00" <> "11" <> compressed_payload = msg
    expected = Base.decode16!("0008000000000000FFFFFFFFFFFFFFFF0F")

    assert_snappy_decompress(compressed_payload, expected)

    msg = "0011FF060000734E6150705901150000CD11E7D53A03000000000000FFFFFFFFFFFFFFFF0F"
    "00" <> "11" <> compressed_payload = msg
    expected = Base.decode16!("3A03000000000000FFFFFFFFFFFFFFFF0F")

    assert_snappy_decompress(compressed_payload, expected)

    # Compressed chunks
    msg = "0011FF060000734E61507059000A0000B3A056EA1100003E0100"
    "00" <> "11" <> compressed_payload = msg
    expected = Base.decode16!("0000000000000000000000000000000000")

    assert_snappy_decompress(compressed_payload, expected)

    msg =
      "011CFF060000734E6150705900220000EF99F84B1C6C4661696C656420746F20756E636F6D7072657373206D657373616765"

    "01" <> "1C" <> compressed_payload = msg

    assert_snappy_decompress(
      compressed_payload,
      "Failed to uncompress message"
    )
  end

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

    # (recver) Receive the stream via the configured stream handler
    {:ok, recv} =
      receive do
        msg -> msg
      after
        1000 -> :timeout
      end

    # (recver) Read the "ping" message from the stream
    {:ok, "ping"} = Libp2p.stream_read(recv)

    # (recver) Write "pong" to the stream
    :ok = Libp2p.stream_write(recv, "pong")

    # (sender) Read the "pong" message from the stream
    {:ok, "pong"} = Libp2p.stream_read(send)

    # Close both streams
    :ok = Libp2p.stream_close(send)
    :ok = Libp2p.stream_close(recv)

    # Close both hosts
    :ok = Libp2p.host_close(sender)
    :ok = Libp2p.host_close(recver)
  end

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

  def try_read_stream(host, iterator, protocol_id, writing_fun) do
    {:ok, peerstore} = Libp2p.host_peerstore(host)

    true = Libp2p.iterator_next(iterator)

    {:ok, node} = Libp2p.iterator_node(iterator)

    if Libp2p.node_tcp(node) != nil do
      {:ok, id} = Libp2p.node_id(node)
      {:ok, addrs} = Libp2p.node_multiaddr(node)

      :ok = Libp2p.peerstore_add_addrs(peerstore, id, addrs, Libp2p.ttl_permanent_addr())

      case Libp2p.host_new_stream(host, id, protocol_id) do
        {:ok, stream} ->
          case Libp2p.stream_read(writing_fun.(stream)) do
            {:ok, msg} -> IO.puts(["\n----->\"#{Base.encode16(msg)}\"<-----\n"])
            _ -> :ok
          end

        _ ->
          :ok
      end
    end

    try_read_stream(host, iterator, protocol_id, writing_fun)
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

    try_read_stream(host, iterator, protocol_id, fn s -> s end)

    :ok = Libp2p.host_close(host)
  end

  @tag :skip
  @tag timeout: :infinity
  test "ping peers" do
    {:ok, host} = Libp2p.host_new()

    # ping peers
    protocol_id = "/eth2/beacon_chain/req/ping/1/ssz_snappy"
    # request body
    msg =
      Base.decode16!(
        "08" <> "FF060000734E61507059" <> "01" <> "0C0000" <> "95A782F5" <> "0A00000000000000"
      )

    :ok = Libp2p.host_set_stream_handler(host, protocol_id)

    {:ok, listener} =
      Libp2p.listen_v5("0.0.0.0:45122", @bootnodes)

    {:ok, iterator} = Libp2p.listener_random_nodes(listener)

    write_msg = fn stream ->
      case Libp2p.stream_write(stream, msg) do
        :ok -> :ok
        {:error, err} -> IO.puts(err)
      end

      stream
    end

    try_read_stream(host, iterator, protocol_id, write_msg)

    :ok = Libp2p.host_close(host)
  end
end
