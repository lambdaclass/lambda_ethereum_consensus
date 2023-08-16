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
      root:
        <<1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 1>>
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
end
