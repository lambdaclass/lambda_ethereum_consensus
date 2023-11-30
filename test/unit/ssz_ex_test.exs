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
    validator = %SszTypes.Validator{
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

    assert_roundtrip(serialized, validator, SszTypes.Validator)
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

    sync = %SszTypes.SyncCommittee{
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

    assert_roundtrip(serialized, sync, SszTypes.SyncCommittee)
  end
end
