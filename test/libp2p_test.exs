defmodule Libp2pTest do
  use ExUnit.Case
  doctest Libp2p

  test "greets the world" do
    assert Libp2p.hello() == :world
  end

  test "my_function is a + 2 * b" do
    assert Libp2p.my_function(5, 124) == 5 + 2 * 124
  end
end
