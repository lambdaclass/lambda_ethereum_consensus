defmodule Libp2pTest do
  use ExUnit.Case
  doctest Libp2p

  test "greets the world" do
    assert Libp2p.hello() == :world
  end

  test "my_function is a + 2 * b" do
    assert Libp2p.my_function(5, 124) == 5 + 2 * 124
  end

  test "Create and destroy host" do
    {:ok, host} = Libp2p.host_new()
    assert host != 0
    :ok = Libp2p.host_close(host)
  end
end
