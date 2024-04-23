defmodule Fixtures.Random do
  @moduledoc """
  Module that binarys random binaries.
  """

  @spec binary(integer()) :: binary()
  def binary(n) when is_integer(n) and n > 0 do
    :rand.bytes(n)
  end

  @spec hash32 :: binary
  def hash32() do
    binary(32)
  end

  @spec root :: binary
  def root() do
    binary(32)
  end

  @spec bls_signature :: binary
  def bls_signature() do
    binary(96)
  end

  @spec sync_committee_bits :: binary
  def sync_committee_bits() do
    binary(64)
  end

  @spec execution_address :: binary
  def execution_address() do
    binary(20)
  end

  @spec uint64 :: pos_integer
  def uint64() do
    :rand.uniform(2 ** 64 - 1)
  end

  @spec uint256 :: pos_integer
  def uint256() do
    :rand.uniform(2 ** 256 - 1)
  end
end
