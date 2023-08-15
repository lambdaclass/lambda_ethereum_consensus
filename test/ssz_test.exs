defmodule SSZTests do
  use ExUnit.Case

  test "encode" do
    value = %{
      epoch: 12345,
      root:
        <<1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 1>>
    }

    encoded = LambdaEthereumConsensus.Ssz.to_ssz(value)
    decoded = LambdaEthereumConsensus.Ssz.from_ssz(encoded)

    assert decoded == value
  end
end
