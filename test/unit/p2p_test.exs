defmodule Unit.P2PTest do
  alias LambdaEthereumConsensus.P2P.Utils
  use ExUnit.Case
  use ExUnitProperties

  property "decode_varint(encode_varint(x)) == {x, \"\"}" do
    check all(int <- integer() |> map(&abs/1)) do
      encoded = Utils.encode_varint(int)
      assert {^int, ""} = Utils.decode_varint(encoded)
    end
  end
end
