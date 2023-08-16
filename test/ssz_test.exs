defmodule SSZTests do
  use ExUnit.Case

  def assert_roundtrip(type, value) do
    {:ok, encoded} = LambdaEthereumConsensus.Ssz.to_ssz(type, value)
    {:ok, decoded} = LambdaEthereumConsensus.Ssz.from_ssz(type, encoded)

    assert decoded == value
  end

  test "serialize and deserialize checkpoint" do
    value = %{
      epoch: 12_345,
      root: Base.decode16!("0100000000000000000000000000000000000000000000000000000000000001")
    }

    assert_roundtrip(Checkpoint, value)
  end

  test "serialize and deserialize fork" do
    value = %{
      epoch: 5125,
      previous_version: <<1, 5, 4, 6>>,
      current_version: <<2, 5, 6, 0>>
    }

    assert_roundtrip(Fork, value)
  end

  test "serialize and deserialize fork data" do
    value = %{
      current_version: <<1, 5, 4, 6>>,
      genesis_validators_root:
        Base.decode16!("2E04DEB062423388AE42D465C4CC14CDD53AE290A7B4541F3217E26E0F039E83")
    }

    assert_roundtrip(ForkData, value)
  end
end
