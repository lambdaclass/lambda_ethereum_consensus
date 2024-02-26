defmodule TypeAliases do
  @moduledoc """
  Type aliases for ssz schemas
  """

  def root, do: {:bytes, 32}
  def epoch, do: {:int, 64}
  def bls_signature, do: {:bytes, 96}
  def slot, do: {:int, 64}
  def commitee_index, do: {:int, 64}
  def validator_index, do: {:int, 64}
  def gwei, do: {:int, 64}
  def participation_flags, do: {:int, 8}
  def withdrawal_index, do: {:int, 64}
  def bls_pubkey, do: {:bytes, 48}
  def execution_address, do: {:bytes, 20}
  def version, do: {:bytes, 4}
  def domain, do: {:bytes, 32}
  def bytes32, do: {:bytes, 32}
  def uint64, do: {:int, 64}
  def hash32, do: {:bytes, 32}
  def uint256, do: {:int, 256}

  def transactions,
    do:
      {:list, {:byte_list, ChainSpec.get("MAX_BYTES_PER_TRANSACTION")},
       ChainSpec.get("MAX_TRANSACTIONS_PER_PAYLOAD")}

  def domain_type, do: {:bytes, 4}
  def fork_digest, do: {:bytes, 4}
end
