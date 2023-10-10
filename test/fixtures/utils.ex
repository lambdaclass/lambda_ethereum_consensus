defmodule Fixtures.Random do
  @moduledoc """
  Module that generates random binaries.
  """

  @spec generate(integer()) :: binary()
  def generate(n) when is_integer(n) and n > 0 do
    :crypto.strong_rand_bytes(n)
  end

  def hash do
    generate(32)
  end

  def root do
    generate(32)
  end

  def bls_signature do
    generate(96)
  end

  def sync_committee_bits do
    generate(64)
  end

  def execution_address do
    generate(20)
  end
end
