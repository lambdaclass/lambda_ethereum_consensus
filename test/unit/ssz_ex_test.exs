defmodule Unit.SSZExTest do
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

  test "serialize and deserialize variable container" do
    pubkey1 =
      <<166, 144, 240, 158, 185, 117, 206, 31, 49, 45, 247, 53, 183, 95, 32, 20, 57, 245, 54, 60,
        97, 78, 24, 81, 227, 157, 191, 150, 163, 202, 1, 72, 46, 131, 80, 54, 55, 203, 11, 160,
        206, 88, 144, 58, 231, 142, 94, 235>>

    pubkey2 =
      <<180, 144, 240, 158, 185, 117, 206, 31, 49, 45, 247, 53, 183, 95, 32, 20, 57, 245, 54, 60,
        97, 78, 24, 81, 227, 157, 191, 150, 163, 202, 1, 72, 46, 131, 80, 54, 55, 203, 11, 160,
        206, 88, 144, 58, 231, 142, 94, 235>>

    pubkey3 =
      <<190, 144, 240, 158, 185, 117, 206, 31, 49, 45, 247, 53, 183, 95, 32, 20, 57, 245, 54, 60,
        97, 78, 24, 81, 227, 157, 191, 150, 163, 202, 1, 72, 46, 131, 80, 54, 55, 203, 11, 160,
        206, 88, 144, 58, 231, 142, 94, 235>>

    pubkey4 =
      <<200, 144, 240, 158, 185, 117, 206, 31, 49, 45, 247, 53, 183, 95, 32, 20, 57, 245, 54, 60,
        97, 78, 24, 81, 227, 157, 191, 150, 163, 202, 1, 72, 46, 131, 80, 54, 55, 203, 11, 160,
        206, 88, 144, 58, 231, 142, 94, 235>>

    sync = %Types.SyncCommittee{
      pubkeys: [pubkey1, pubkey2, pubkey3],
      aggregate_pubkey: pubkey4
    }

    serialized =
      <<52, 0, 0, 0, 200, 144, 240, 158, 185, 117, 206, 31, 49, 45, 247, 53, 183, 95, 32, 20, 57,
        245, 54, 60, 97, 78, 24, 81, 227, 157, 191, 150, 163, 202, 1, 72, 46, 131, 80, 54, 55,
        203, 11, 160, 206, 88, 144, 58, 231, 142, 94, 235, 166, 144, 240, 158, 185, 117, 206, 31,
        49, 45, 247, 53, 183, 95, 32, 20, 57, 245, 54, 60, 97, 78, 24, 81, 227, 157, 191, 150,
        163, 202, 1, 72, 46, 131, 80, 54, 55, 203, 11, 160, 206, 88, 144, 58, 231, 142, 94, 235,
        180, 144, 240, 158, 185, 117, 206, 31, 49, 45, 247, 53, 183, 95, 32, 20, 57, 245, 54, 60,
        97, 78, 24, 81, 227, 157, 191, 150, 163, 202, 1, 72, 46, 131, 80, 54, 55, 203, 11, 160,
        206, 88, 144, 58, 231, 142, 94, 235, 190, 144, 240, 158, 185, 117, 206, 31, 49, 45, 247,
        53, 183, 95, 32, 20, 57, 245, 54, 60, 97, 78, 24, 81, 227, 157, 191, 150, 163, 202, 1, 72,
        46, 131, 80, 54, 55, 203, 11, 160, 206, 88, 144, 58, 231, 142, 94, 235>>

    assert_roundtrip(serialized, sync, Types.SyncCommittee)
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

    truncated_encoded_bytes = <<11::4>>
    expected_encoded_bytes = <<11>>
    assert {:ok, decoded_bytes} = SszEx.decode(truncated_encoded_bytes, {:bitlist, 31})
    assert {:ok, ^expected_encoded_bytes} = SszEx.encode(decoded_bytes, {:bitlist, 31})

    truncated_encoded_bytes = <<10::4>>
    expected_encoded_bytes = <<10>>
    assert {:ok, decoded_bytes} = SszEx.decode(truncated_encoded_bytes, {:bitlist, 31})
    assert {:ok, ^expected_encoded_bytes} = SszEx.encode(decoded_bytes, {:bitlist, 31})

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

    encoded_bytes = <<255, 255, 255, 255, 1>>
    assert {:error, _msg} = SszEx.decode(encoded_bytes, {:bitvector, 33})

    encoded_bytes = <<0>>
    assert {:error, _msg} = SszEx.decode(encoded_bytes, {:bitvector, 9})
  end
end
