defmodule Unit.SSZExTest do
  alias LambdaEthereumConsensus.Utils.Diff

  alias Types.BeaconBlock
  alias Types.BeaconBlockBody
  alias Types.Checkpoint
  alias Types.Eth1Data
  alias Types.ExecutionPayload
  alias Types.SyncAggregate

  alias LambdaEthereumConsensus.SszEx
  use ExUnit.Case

  def assert_roundtrip(serialized, deserialized, schema) do
    assert {:ok, ^serialized} = SszEx.encode(deserialized, schema)
    assert {:ok, deserialized} === SszEx.decode(serialized, schema)
  end

  def error_assert_roundtrip(serialized, deserialized, schema, error_message) do
    assert {:error, ^error_message} = SszEx.encode(deserialized, schema)
    assert {:error, ^error_message} = SszEx.decode(serialized, schema)
  end

  test "packing a list of uints" do
    list_1 = [1, 2, 3, 4, 5]

    expected_1 =
      <<1, 2, 3, 4, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0>>

    actual_1 = SszEx.pack(list_1, {:list, {:int, 8}, 5})
    assert expected_1 == actual_1

    list_2 = [
      18_446_744_073_709_551_595,
      18_446_744_073_709_551_596,
      18_446_744_073_709_551_597,
      18_446_744_073_709_551_598,
      18_446_744_073_709_551_599,
      18_446_744_073_709_551_600,
      18_446_744_073_709_551_601,
      18_446_744_073_709_551_603,
      18_446_744_073_709_551_604,
      18_446_744_073_709_551_605,
      18_446_744_073_709_551_606,
      18_446_744_073_709_551_607,
      18_446_744_073_709_551_608,
      18_446_744_073_709_551_609,
      18_446_744_073_709_551_610,
      18_446_744_073_709_551_611,
      18_446_744_073_709_551_612,
      18_446_744_073_709_551_613,
      18_446_744_073_709_551_614,
      18_446_744_073_709_551_615
    ]

    expected_2 =
      <<235, 255, 255, 255, 255, 255, 255, 255, 236, 255, 255, 255, 255, 255, 255, 255, 237, 255,
        255, 255, 255, 255, 255, 255, 238, 255, 255, 255, 255, 255, 255, 255, 239, 255, 255, 255,
        255, 255, 255, 255, 240, 255, 255, 255, 255, 255, 255, 255, 241, 255, 255, 255, 255, 255,
        255, 255, 243, 255, 255, 255, 255, 255, 255, 255, 244, 255, 255, 255, 255, 255, 255, 255,
        245, 255, 255, 255, 255, 255, 255, 255, 246, 255, 255, 255, 255, 255, 255, 255, 247, 255,
        255, 255, 255, 255, 255, 255, 248, 255, 255, 255, 255, 255, 255, 255, 249, 255, 255, 255,
        255, 255, 255, 255, 250, 255, 255, 255, 255, 255, 255, 255, 251, 255, 255, 255, 255, 255,
        255, 255, 252, 255, 255, 255, 255, 255, 255, 255, 253, 255, 255, 255, 255, 255, 255, 255,
        254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255>>

    actual_2 = SszEx.pack(list_2, {:list, {:int, 64}, 15})
    assert expected_2 == actual_2
  end

  test "packing a list of booleans" do
    list = [true, false, true, false, true]

    expected =
      <<1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0>>

    actual = SszEx.pack(list, {:list, :bool, 5})
    assert expected == actual
  end

  test "merklelization of chunks" do
    # Reference:  https://github.com/ralexstokes/ssz-rs/blob/1f94d5dfc70c86dab672e91ac46af04a5f96c342/ssz-rs/src/merkleization/mod.rs#L371
    #            https://github.com/ralexstokes/ssz-rs/blob/1f94d5dfc70c86dab672e91ac46af04a5f96c342/ssz-rs/src/merkleization/mod.rs#L416
    zero = <<0::256>>

    chunks = zero
    root = SszEx.merkleize_chunks(chunks)
    expected_value = "0000000000000000000000000000000000000000000000000000000000000000"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = zero <> zero
    root = chunks |> SszEx.merkleize_chunks(2)
    expected_value = "f5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b"
    assert root |> Base.encode16(case: :lower) == expected_value

    ones = 0..31 |> Enum.reduce(<<>>, fn _, acc -> <<1>> <> acc end)

    chunks = ones <> ones
    root = chunks |> SszEx.merkleize_chunks(2)
    expected_value = "7c8975e1e60a5c8337f28edf8c33c3b180360b7279644a9bc1af3c51e6220bf5"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = zero <> zero <> zero <> zero
    root = chunks |> SszEx.merkleize_chunks(4)
    expected_value = "db56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = zero <> zero <> zero <> zero <> zero <> zero <> zero <> zero
    root = chunks |> SszEx.merkleize_chunks(8)
    expected_value = "c78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = ones
    root = chunks |> SszEx.merkleize_chunks(4)
    expected_value = "29797eded0e83376b70f2bf034cc0811ae7f1414653b1d720dfd18f74cf13309"
    assert root |> Base.encode16(case: :lower) == expected_value

    twos = 0..31 |> Enum.reduce(<<>>, fn _, acc -> <<2>> <> acc end)

    chunks = twos
    root = chunks |> SszEx.merkleize_chunks(8)
    expected_value = "fa4cf775712aa8a2fe5dcb5a517d19b2e9effcf58ff311b9fd8e4a7d308e6d00"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = ones <> ones <> ones
    root = chunks |> SszEx.merkleize_chunks(4)
    expected_value = "65aa94f2b59e517abd400cab655f42821374e433e41b8fe599f6bb15484adcec"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = ones <> ones <> ones <> ones <> ones
    root = chunks |> SszEx.merkleize_chunks(8)
    expected_value = "0ae67e34cba4ad2bbfea5dc39e6679b444021522d861fab00f05063c54341289"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = ones <> ones <> ones <> ones <> ones <> ones
    root = chunks |> SszEx.merkleize_chunks(8)
    expected_value = "0ef7df63c204ef203d76145627b8083c49aa7c55ebdee2967556f55a4f65a238"
    assert root |> Base.encode16(case: :lower) == expected_value

    ## Large Leaf Count

    chunks = ones <> ones <> ones <> ones <> ones
    root = chunks |> SszEx.merkleize_chunks(2 ** 10)
    expected_value = "2647cb9e26bd83eeb0982814b2ac4d6cc4a65d0d98637f1a73a4c06d3db0e6ce"
    assert root |> Base.encode16(case: :lower) == expected_value
  end

  test "merklelization of chunks with virtual padding" do
    zero = <<0::256>>

    chunks = zero
    root = SszEx.merkleize_chunks_with_virtual_padding(chunks, 1)
    expected_value = "0000000000000000000000000000000000000000000000000000000000000000"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = zero <> zero
    root = chunks |> SszEx.merkleize_chunks_with_virtual_padding(2)
    expected_value = "f5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b"
    assert root |> Base.encode16(case: :lower) == expected_value

    ones = 0..31 |> Enum.reduce(<<>>, fn _, acc -> <<1>> <> acc end)

    chunks = ones <> ones
    root = chunks |> SszEx.merkleize_chunks_with_virtual_padding(2)
    expected_value = "7c8975e1e60a5c8337f28edf8c33c3b180360b7279644a9bc1af3c51e6220bf5"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = zero <> zero <> zero <> zero
    root = chunks |> SszEx.merkleize_chunks_with_virtual_padding(4)
    expected_value = "db56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = zero <> zero <> zero <> zero <> zero <> zero <> zero <> zero
    root = chunks |> SszEx.merkleize_chunks_with_virtual_padding(8)
    expected_value = "c78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = ones
    root = chunks |> SszEx.merkleize_chunks_with_virtual_padding(4)
    expected_value = "29797eded0e83376b70f2bf034cc0811ae7f1414653b1d720dfd18f74cf13309"
    assert root |> Base.encode16(case: :lower) == expected_value

    twos = 0..31 |> Enum.reduce(<<>>, fn _, acc -> <<2>> <> acc end)

    chunks = twos
    root = chunks |> SszEx.merkleize_chunks_with_virtual_padding(8)
    expected_value = "fa4cf775712aa8a2fe5dcb5a517d19b2e9effcf58ff311b9fd8e4a7d308e6d00"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = ones <> ones <> ones
    root = chunks |> SszEx.merkleize_chunks_with_virtual_padding(4)
    expected_value = "65aa94f2b59e517abd400cab655f42821374e433e41b8fe599f6bb15484adcec"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = ones <> ones <> ones <> ones <> ones
    root = chunks |> SszEx.merkleize_chunks_with_virtual_padding(8)
    expected_value = "0ae67e34cba4ad2bbfea5dc39e6679b444021522d861fab00f05063c54341289"
    assert root |> Base.encode16(case: :lower) == expected_value

    chunks = ones <> ones <> ones <> ones <> ones <> ones
    root = chunks |> SszEx.merkleize_chunks_with_virtual_padding(8)
    expected_value = "0ef7df63c204ef203d76145627b8083c49aa7c55ebdee2967556f55a4f65a238"
    assert root |> Base.encode16(case: :lower) == expected_value

    ## Large Leaf Count

    chunks = ones <> ones <> ones <> ones <> ones
    root = chunks |> SszEx.merkleize_chunks_with_virtual_padding(2 ** 10)
    expected_value = "2647cb9e26bd83eeb0982814b2ac4d6cc4a65d0d98637f1a73a4c06d3db0e6ce"
    assert root |> Base.encode16(case: :lower) == expected_value
  end

  test "hash tree root of list of uints" do
    ## reference: https://github.com/ralexstokes/ssz-rs/blob/1f94d5dfc70c86dab672e91ac46af04a5f96c342/ssz-rs/src/merkleization/mod.rs#L459

    list = Stream.cycle([65_535]) |> Enum.take(316)
    {:ok, root} = list |> SszEx.hash_tree_root({:list, {:int, 16}, 1024})
    expected_value = "d20d2246e1438d88de46f6f41c7b041f92b673845e51f2de93b944bf599e63b1"
    assert root |> Base.encode16(case: :lower) == expected_value

    ## hash tree root of empty list
    {:ok, root} = [] |> SszEx.hash_tree_root({:list, {:int, 16}, 1024})
    expected_value = "c9eece3e14d3c3db45c38bbf69a4cb7464981e2506d8424a0ba450dad9b9af30"
    assert root |> Base.encode16(case: :lower) == expected_value
  end

  test "hash tree root of list of composite objects" do
    ## list of containers
    checkpoint = %Checkpoint{
      epoch: 12_345,
      root: Base.decode16!("0100000000000000000000000000000000000000000000000000000000000001")
    }

    list = [checkpoint, checkpoint]
    schema = {:list, Checkpoint, 8}
    SszEx.hash_tree_root!(list, schema)

    ## list of lists
    list1 = Stream.cycle([65_535]) |> Enum.take(316)
    list2 = Stream.cycle([65_530]) |> Enum.take(316)
    list = [list1, list2]
    schema = {:list, {:list, {:int, 16}, 1024}, 1024}
    SszEx.hash_tree_root!(list, schema)

    ## list of list of lists
    list1 = Stream.cycle([65_535]) |> Enum.take(316)
    list2 = Stream.cycle([65_530]) |> Enum.take(316)
    list3 = [list1, list2]
    list4 = [list1, list2]
    list = [list3, list4]
    schema = {:list, {:list, {:list, {:int, 16}, 1024}, 1024}, 128}
    SszEx.hash_tree_root!(list, schema)

    ## list of list of vectors
    vector1 = Stream.cycle([65_535]) |> Enum.take(316)
    vector2 = Stream.cycle([65_530]) |> Enum.take(316)
    list1 = [vector1, vector2]
    list2 = [vector1, vector2]
    list = [list1, list2]
    schema = {:list, {:list, {:vector, {:int, 16}, 316}, 1024}, 136}
    SszEx.hash_tree_root!(list, schema)

    ## list of vector of lists
    list1 = Stream.cycle([65_535]) |> Enum.take(316)
    list2 = Stream.cycle([65_530]) |> Enum.take(316)
    vector1 = [list1, list2]
    vector2 = [list1, list2]
    list = [vector1, vector2]
    schema = {:list, {:vector, {:list, {:int, 16}, 1024}, 2}, 32}
    SszEx.hash_tree_root!(list, schema)

    ## list of vector of vector
    vector1 = Stream.cycle([65_535]) |> Enum.take(316)
    vector2 = Stream.cycle([65_530]) |> Enum.take(316)
    vector3 = [vector1, vector2]
    vector4 = [vector1, vector2]
    list = [vector3, vector4]
    schema = {:list, {:vector, {:vector, {:int, 16}, 316}, 2}, 32}
    SszEx.hash_tree_root!(list, schema)
  end

  test "hash tree root of vector of composite objects" do
    ## list of containers
    checkpoint = %Checkpoint{
      epoch: 12_345,
      root: Base.decode16!("0100000000000000000000000000000000000000000000000000000000000001")
    }

    vector = [checkpoint, checkpoint]
    schema = {:vector, Checkpoint, 2}
    SszEx.hash_tree_root!(vector, schema)

    ## vector of vectors
    vector1 = Stream.cycle([65_535]) |> Enum.take(316)
    vector2 = Stream.cycle([65_530]) |> Enum.take(316)
    vector = [vector1, vector2]
    schema = {:vector, {:vector, {:int, 16}, 316}, 2}
    SszEx.hash_tree_root!(vector, schema)

    ## vector of vector of vectors
    vector1 = Stream.cycle([65_535]) |> Enum.take(316)
    vector2 = Stream.cycle([65_530]) |> Enum.take(316)
    vector3 = [vector1, vector2]
    vector4 = [vector1, vector2]
    vector = [vector3, vector4]
    schema = {:vector, {:vector, {:vector, {:int, 16}, 316}, 2}, 2}
    SszEx.hash_tree_root!(vector, schema)

    ## vector of list of vectors
    vector1 = Stream.cycle([65_535]) |> Enum.take(316)
    vector2 = Stream.cycle([65_530]) |> Enum.take(316)
    list1 = [vector1, vector2]
    list2 = [vector1, vector2]
    vector = [list1, list2]
    schema = {:vector, {:list, {:vector, {:int, 16}, 316}, 32}, 2}
    SszEx.hash_tree_root!(vector, schema)

    ## vector of vector of lists
    list1 = Stream.cycle([65_535]) |> Enum.take(316)
    list2 = Stream.cycle([65_530]) |> Enum.take(316)
    vector1 = [list1, list2]
    vector2 = [list1, list2]
    vector = [vector1, vector2]
    schema = {:vector, {:vector, {:list, {:int, 16}, 1024}, 2}, 2}
    SszEx.hash_tree_root!(vector, schema)

    ## vector of list of lists
    list1 = Stream.cycle([65_535]) |> Enum.take(316)
    list2 = Stream.cycle([65_530]) |> Enum.take(316)
    list3 = [list1, list2]
    list4 = [list1, list2]
    vector = [list3, list4]
    schema = {:vector, {:list, {:list, {:int, 16}, 1024}, 8}, 2}
    SszEx.hash_tree_root!(vector, schema)
  end

  test "serialize and deserialize uint" do
    assert_roundtrip(<<5>>, 5, {:int, 8})
    assert_roundtrip(<<5, 0>>, 5, {:int, 16})
    assert_roundtrip(<<5, 0, 0, 0>>, 5, {:int, 32})
    assert_roundtrip(<<5, 0, 0, 0, 0, 0, 0, 0>>, 5, {:int, 64})

    assert_roundtrip(<<20, 1>>, 276, {:int, 16})
    assert_roundtrip(<<20, 1, 0, 0>>, 276, {:int, 32})
    assert_roundtrip(<<20, 1, 0, 0, 0, 0, 0, 0>>, 276, {:int, 64})
  end

  test "serialize and deserialize bool" do
    assert_roundtrip(<<1>>, true, :bool)
    assert_roundtrip(<<0>>, false, :bool)
  end

  test "serialize and deserialize nested container" do
    checkpoint_source = %Types.Checkpoint{
      epoch: 3_776_037_760_046_644_755,
      root:
        <<29, 22, 191, 147, 188, 238, 162, 89, 147, 162, 202, 111, 169, 162, 84, 95, 194, 85, 54,
          172, 44, 74, 37, 128, 248, 21, 86, 246, 151, 54, 24, 54>>
    }

    checkpoint_target = %Types.Checkpoint{
      epoch: 2_840_053_453_521_072_037,
      root:
        <<15, 174, 23, 120, 4, 9, 2, 116, 67, 73, 254, 53, 197, 3, 191, 166, 104, 34, 121, 2, 57,
          69, 75, 69, 254, 237, 132, 68, 254, 49, 127, 175>>
    }

    attestation_data = %Types.AttestationData{
      slot: 5_057_010_135_270_197_978,
      index: 6_920_931_864_607_509_210,
      beacon_block_root:
        <<31, 38, 101, 174, 248, 168, 116, 226, 15, 39, 218, 148, 42, 8, 80, 80, 241, 149, 162,
          32, 176, 208, 120, 120, 89, 123, 136, 115, 154, 28, 21, 174>>,
      source: checkpoint_source,
      target: checkpoint_target
    }

    indexed_attestation = %Types.IndexedAttestation{
      attesting_indices: [15_833_676_831_095_072_535, 7_978_643_446_947_046_229],
      data: attestation_data,
      signature:
        <<46, 244, 83, 164, 182, 222, 218, 247, 8, 186, 138, 100, 5, 96, 34, 117, 134, 123, 219,
          188, 181, 11, 209, 57, 207, 24, 249, 42, 74, 27, 228, 97, 73, 46, 219, 202, 122, 149,
          135, 30, 91, 126, 180, 69, 129, 170, 147, 142, 242, 27, 233, 63, 242, 7, 144, 8, 192,
          165, 194, 220, 77, 247, 128, 107, 41, 199, 166, 59, 34, 160, 222, 114, 250, 250, 3, 130,
          145, 8, 45, 65, 13, 82, 44, 80, 30, 181, 239, 54, 152, 237, 244, 72, 231, 179, 239, 22>>
    }

    serialized =
      <<228, 0, 0, 0, 218, 138, 84, 194, 236, 27, 46, 70, 218, 202, 156, 184, 220, 22, 12, 96, 31,
        38, 101, 174, 248, 168, 116, 226, 15, 39, 218, 148, 42, 8, 80, 80, 241, 149, 162, 32, 176,
        208, 120, 120, 89, 123, 136, 115, 154, 28, 21, 174, 19, 190, 10, 34, 86, 46, 103, 52, 29,
        22, 191, 147, 188, 238, 162, 89, 147, 162, 202, 111, 169, 162, 84, 95, 194, 85, 54, 172,
        44, 74, 37, 128, 248, 21, 86, 246, 151, 54, 24, 54, 165, 175, 62, 152, 145, 229, 105, 39,
        15, 174, 23, 120, 4, 9, 2, 116, 67, 73, 254, 53, 197, 3, 191, 166, 104, 34, 121, 2, 57,
        69, 75, 69, 254, 237, 132, 68, 254, 49, 127, 175, 46, 244, 83, 164, 182, 222, 218, 247, 8,
        186, 138, 100, 5, 96, 34, 117, 134, 123, 219, 188, 181, 11, 209, 57, 207, 24, 249, 42, 74,
        27, 228, 97, 73, 46, 219, 202, 122, 149, 135, 30, 91, 126, 180, 69, 129, 170, 147, 142,
        242, 27, 233, 63, 242, 7, 144, 8, 192, 165, 194, 220, 77, 247, 128, 107, 41, 199, 166, 59,
        34, 160, 222, 114, 250, 250, 3, 130, 145, 8, 45, 65, 13, 82, 44, 80, 30, 181, 239, 54,
        152, 237, 244, 72, 231, 179, 239, 22, 23, 39, 193, 253, 47, 133, 188, 219, 85, 227, 198,
        60, 241, 213, 185, 110>>

    assert_roundtrip(serialized, indexed_attestation, Types.IndexedAttestation)
  end

  test "serialize and deserialize list" do
    # for test purposes only, do not use in practice
    assert_roundtrip(<<1, 1, 0>>, [true, true, false], {:list, :bool, 3})

    assert_roundtrip(
      <<230, 0, 0, 0, 124, 1, 0, 0, 11, 2, 0, 0>>,
      [230, 380, 523],
      {:list, {:int, 32}, 3}
    )

    variable_list = [[5, 6], [7, 8], [9, 10]]
    encoded_variable_list = <<12, 0, 0, 0, 14, 0, 0, 0, 16, 0, 0, 0, 5, 6, 7, 8, 9, 10>>
    assert_roundtrip(encoded_variable_list, variable_list, {:list, {:list, {:int, 8}, 2}, 3})

    variable_list = [[380, 6], [480, 8], [580, 10]]

    encoded_variable_list =
      <<12, 0, 0, 0, 28, 0, 0, 0, 44, 0, 0, 0, 124, 1, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0,
        224, 1, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 68, 2, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0,
        0, 0, 0>>

    assert_roundtrip(encoded_variable_list, variable_list, {:list, {:list, {:int, 64}, 2}, 3})

    error_assert_roundtrip(
      <<230, 0, 0, 0, 124, 1, 0, 0, 11, 2, 0, 0, 127, 91, 0, 0>>,
      [230, 380, 523, 23_423],
      {:list, {:int, 32}, 3},
      "invalid max_size of list"
    )

    # length < max_size
    assert_roundtrip(<<2, 0, 0, 0>>, [2], {:list, {:int, 32}, 53})
    # empty list
    assert_roundtrip(<<>>, [], {:list, {:int, 32}, 6})
  end

  test "serialize and deserialize container only with fixed parts" do
    validator = %Types.Validator{
      pubkey:
        <<166, 144, 240, 158, 185, 117, 206, 31, 49, 45, 247, 53, 183, 95, 32, 20, 57, 245, 54,
          60, 97, 78, 24, 81, 227, 157, 191, 150, 163, 202, 1, 72, 46, 131, 80, 54, 55, 203, 11,
          160, 206, 88, 144, 58, 231, 142, 94, 235>>,
      withdrawal_credentials:
        <<31, 83, 167, 245, 158, 202, 157, 114, 98, 134, 215, 52, 106, 152, 108, 188, 15, 122, 21,
          35, 113, 166, 17, 202, 159, 46, 180, 113, 98, 99, 233, 2>>,
      effective_balance: 2_281_329_295_298_915_107,
      slashed: false,
      activation_eligibility_epoch: 8_916_476_893_047_043_501,
      activation_epoch: 11_765_006_084_061_081_232,
      exit_epoch: 14_221_179_644_044_541_938,
      withdrawable_epoch: 11_813_934_873_299_048_632
    }

    serialized =
      <<166, 144, 240, 158, 185, 117, 206, 31, 49, 45, 247, 53, 183, 95, 32, 20, 57, 245, 54, 60,
        97, 78, 24, 81, 227, 157, 191, 150, 163, 202, 1, 72, 46, 131, 80, 54, 55, 203, 11, 160,
        206, 88, 144, 58, 231, 142, 94, 235, 31, 83, 167, 245, 158, 202, 157, 114, 98, 134, 215,
        52, 106, 152, 108, 188, 15, 122, 21, 35, 113, 166, 17, 202, 159, 46, 180, 113, 98, 99,
        233, 2, 35, 235, 251, 53, 232, 232, 168, 31, 0, 173, 53, 12, 34, 126, 176, 189, 123, 144,
        46, 197, 36, 179, 178, 69, 163, 242, 127, 74, 10, 138, 199, 91, 197, 184, 216, 150, 162,
        44, 135, 243, 163>>

    assert_roundtrip(serialized, validator, Types.Validator)
  end

  @root_size 32
  @signature_size 96
  @default_signature <<0::size(@signature_size * 8)>>
  @default_root <<0::size(@root_size * 8)>>
  @default_hash @default_root

  test "default block" do
    default = SszEx.default(BeaconBlock)

    expected = %BeaconBlock{
      slot: 0,
      proposer_index: 0,
      parent_root: @default_root,
      state_root: @default_root,
      body: %BeaconBlockBody{
        randao_reveal: @default_signature,
        eth1_data: %Eth1Data{
          deposit_root: @default_root,
          deposit_count: 0,
          block_hash: @default_hash
        },
        graffiti: <<0::size(32 * 8)>>,
        proposer_slashings: [],
        attester_slashings: [],
        attestations: [],
        deposits: [],
        voluntary_exits: [],
        sync_aggregate: %SyncAggregate{
          sync_committee_bits: <<0::size(ChainSpec.get("SYNC_COMMITTEE_SIZE"))>>,
          sync_committee_signature: @default_signature
        },
        execution_payload: %ExecutionPayload{
          parent_hash: @default_hash,
          fee_recipient: <<0::size(20 * 8)>>,
          state_root: @default_root,
          receipts_root: @default_root,
          logs_bloom: <<0::size(ChainSpec.get("BYTES_PER_LOGS_BLOOM") * 8)>>,
          prev_randao: <<0::size(32 * 8)>>,
          block_number: 0,
          gas_limit: 0,
          gas_used: 0,
          timestamp: 0,
          extra_data: <<>>,
          base_fee_per_gas: 0,
          block_hash: @default_hash,
          transactions: [],
          withdrawals: [],
          blob_gas_used: 0,
          excess_blob_gas: 0
        },
        bls_to_execution_changes: [],
        blob_kzg_commitments: []
      }
    }

    assert Diff.diff(default, expected) == :unchanged
  end

  test "serialize and deserialize bitlist" do
    encoded_bytes = <<160, 92, 1>>
    assert {:ok, decoded_bytes} = SszEx.decode(encoded_bytes, {:bitlist, 16})
    assert {:ok, ^encoded_bytes} = SszEx.encode(decoded_bytes, {:bitlist, 16})

    encoded_bytes = <<255, 1>>
    assert {:ok, decoded_bytes} = SszEx.decode(encoded_bytes, {:bitlist, 16})
    assert {:ok, ^encoded_bytes} = SszEx.encode(decoded_bytes, {:bitlist, 16})

    encoded_bytes = <<31>>
    assert {:ok, decoded_bytes} = SszEx.decode(encoded_bytes, {:bitlist, 16})
    assert {:ok, ^encoded_bytes} = SszEx.encode(decoded_bytes, {:bitlist, 16})

    encoded_bytes = <<1>>
    assert {:ok, decoded_bytes} = SszEx.decode(encoded_bytes, {:bitlist, 31})
    assert {:ok, ^encoded_bytes} = SszEx.encode(decoded_bytes, {:bitlist, 31})

    encoded_bytes = <<106, 141, 117, 7>>
    assert {:ok, decoded_bytes} = SszEx.decode(encoded_bytes, {:bitlist, 31})
    assert {:ok, ^encoded_bytes} = SszEx.encode(decoded_bytes, {:bitlist, 31})

    encoded_bytes = <<7>>
    assert {:error, _msg} = SszEx.decode(encoded_bytes, {:bitlist, 1})

    encoded_bytes = <<124, 3>>
    assert {:error, _msg} = SszEx.decode(encoded_bytes, {:bitlist, 1})

    encoded_bytes = <<0>>
    assert {:error, _msg} = SszEx.decode(encoded_bytes, {:bitlist, 1})
    assert {:error, _msg} = SszEx.decode(encoded_bytes, {:bitlist, 16})
  end

  test "serialize and deserialize bitvector" do
    encoded_bytes = <<255, 255>>
    assert {:ok, decoded_bytes} = SszEx.decode(encoded_bytes, {:bitvector, 16})
    assert {:ok, ^encoded_bytes} = SszEx.encode(decoded_bytes, {:bitvector, 16})

    encoded_bytes = <<0, 0>>
    assert {:ok, decoded_bytes} = SszEx.decode(encoded_bytes, {:bitvector, 16})
    assert {:ok, ^encoded_bytes} = SszEx.encode(decoded_bytes, {:bitvector, 16})

    encoded_bytes = <<255, 255, 255, 255, 255, 1>>
    assert {:error, _msg} = SszEx.decode(encoded_bytes, {:bitvector, 33})

    encoded_bytes = <<0>>
    assert {:error, _msg} = SszEx.decode(encoded_bytes, {:bitvector, 9})
  end
end
