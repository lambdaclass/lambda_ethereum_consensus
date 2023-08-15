defmodule SSZTests do
  use ExUnit.Case

  test "serialize and deserialize checkpoint object" do
    value = %{
      epoch: 12_345,
      root:
        <<1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 1>>
    }

    {:ok, encoded} = LambdaEthereumConsensus.Ssz.to_ssz(Checkpoint, value)
    {:ok, decoded} = LambdaEthereumConsensus.Ssz.from_ssz(encoded)

    assert decoded == value
  end
end
