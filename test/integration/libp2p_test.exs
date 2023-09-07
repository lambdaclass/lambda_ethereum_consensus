defmodule Integration.Libp2pTest do
  use ExUnit.Case
  doctest Libp2p

  # Mainnet
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
    case Libp2p.subscription_next(sub) do
      {:ok, msg} ->
        # NOTE: gossip messages are Snappy-compressed with BLOCK format (not frame)
        msg
        |> Libp2p.message_data()
        |> then(fn {:ok, d} -> d end)
        |> Base.encode16()
        |> then(&IO.puts(["\"#{&1}\""]))

      {:error, err} ->
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
