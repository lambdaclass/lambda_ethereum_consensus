defmodule SSZTests do
  use ExUnit.Case

  def assert_roundtrip(%type{} = value) do
    {:ok, encoded} = Ssz.to_ssz(value)
    {:ok, decoded} = Ssz.from_ssz(encoded, type)

    assert decoded == value
  end

  test "serialize and deserialize checkpoint" do
    value = %SszTypes.Checkpoint{
      epoch: 12_345,
      root: Base.decode16!("0100000000000000000000000000000000000000000000000000000000000001")
    }

    assert_roundtrip(value)
  end

  test "serialize and deserialize fork" do
    value = %SszTypes.Fork{
      epoch: 5125,
      previous_version: <<1, 5, 4, 6>>,
      current_version: <<2, 5, 6, 0>>
    }

    assert_roundtrip(value)
  end

  test "serialize and deserialize fork data" do
    value = %SszTypes.ForkData{
      current_version: <<1, 5, 4, 6>>,
      genesis_validators_root:
        Base.decode16!("2E04DEB062423388AE42D465C4CC14CDD53AE290A7B4541F3217E26E0F039E83")
    }

    assert_roundtrip(value)
  end

  test "serialize and deserialize indexed attestation" do
    # test c:minimal f:capella r:ssz_static h:IndexedAttestation s:ssz_random_chaos -> case_23
    value = %SszTypes.IndexedAttestationMainnet{
      attesting_indices: [
        13_329_396_561_159_955_693,
        4_052_468_117_648_402_348,
        13_451_759_518_998_307_700
      ],
      data: %SszTypes.AttestationData{
        slot: 10_610_124_296_493_688_335,
        index: 0,
        beacon_block_root:
          Base.decode16!("08C7979023DADA9DB03775129CCF942CFA93C9B80323C9C6D08E3B6AA606D945"),
        source: %SszTypes.Checkpoint{
          epoch: 18_446_744_073_709_551_615,
          root: Base.decode16!("32B67DD3EBC8C35409FACF0BE72E084DF7C9A2709AD6DAD1AA6C391906E8DB5E")
        },
        target: %SszTypes.Checkpoint{
          epoch: 6_677_446_695_536_220_332,
          root: Base.decode16!("0000000000000000000000000000000000000000000000000000000000000000")
        }
      },
      signature:
        Base.decode16!(
          "0ABCB9612CCC4C7FC56D04CCA3454ED88B062885D62CC3B6D4D4D9CE01AB0DFA25027125D07A160AEC95BBB6F88FA2E818C5A6FAAC5443A63000A7409932FBC46927DD547050A335822417F8F283DC23D91B0A6C2B4DAAB36F07B9542D52F79D"
        )
    }

    IO.inspect(value, limit: :infinity)

    assert_roundtrip(value)
  end
end
