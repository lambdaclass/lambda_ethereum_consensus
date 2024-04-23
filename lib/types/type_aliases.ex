defmodule TypeAliases do
  @moduledoc """
  Type aliases for ssz schemas
  """

  def root(), do: {:byte_vector, 32}
  def epoch(), do: {:int, 64}
  def bls_signature(), do: {:byte_vector, 96}
  def slot(), do: {:int, 64}
  def commitee_index(), do: {:int, 64}
  def validator_index(), do: {:int, 64}
  def gwei(), do: {:int, 64}
  def participation_flags(), do: {:int, 8}
  def withdrawal_index(), do: {:int, 64}
  def bls_pubkey(), do: {:byte_vector, 48}
  def execution_address(), do: {:byte_vector, 20}
  def version(), do: {:byte_vector, 4}
  def domain(), do: {:byte_vector, 32}
  def domain_type(), do: {:byte_vector, 4}
  def fork_digest(), do: {:byte_vector, 4}
  def blob_index(), do: uint64()

  def blob(),
    do:
      {:byte_vector,
       Constants.bytes_per_field_element() * ChainSpec.get("FIELD_ELEMENTS_PER_BLOB")}

  def kzg_commitment(), do: {:byte_vector, 48}
  def kzg_proof(), do: {:byte_vector, 48}

  def bytes32(), do: {:byte_vector, 32}
  def uint64(), do: {:int, 64}
  def hash32(), do: {:byte_vector, 32}
  def uint256(), do: {:int, 256}

  def transactions() do
    transaction = {:byte_list, ChainSpec.get("MAX_BYTES_PER_TRANSACTION")}
    {:list, transaction, ChainSpec.get("MAX_TRANSACTIONS_PER_PAYLOAD")}
  end

  def beacon_blocks_by_root_request(),
    do: {:list, TypeAliases.root(), ChainSpec.get("MAX_REQUEST_BLOCKS")}

  def blob_sidecars_by_root_request(),
    do: {:list, Types.BlobIdentifier, ChainSpec.get("MAX_REQUEST_BLOB_SIDECARS")}

  def error_message(), do: {:byte_list, 256}
end
