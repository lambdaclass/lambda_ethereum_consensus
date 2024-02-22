defmodule Types do
  @moduledoc """
  Lists some types used in SSZ structs.
  """

  # Primitive types
  ## Integer types
  @type uint8 :: 0..unquote(2 ** 8 - 1)
  @type uint16 :: 0..unquote(2 ** 16 - 1)
  @type uint32 :: 0..unquote(2 ** 32 - 1)
  @type uint64 :: 0..unquote(2 ** 64 - 1)
  @type uint256 :: 0..unquote(2 ** 256 - 1)

  ## Binary types
  @type bytes1 :: <<_::8>>
  @type bytes4 :: <<_::32>>
  @type bytes8 :: <<_::64>>
  @type bytes20 :: <<_::160>>
  @type bytes32 :: <<_::256>>
  @type bytes48 :: <<_::384>>
  @type bytes96 :: <<_::768>>
  # bitlists are stored in SSZ format
  @type bitlist :: binary
  @type bitvector :: binary

  ## Aliases
  @type slot :: uint64
  @type epoch :: uint64
  @type commitee_index :: uint64
  @type validator_index :: uint64
  @type gwei :: uint64
  @type root :: bytes32
  @type hash32 :: bytes32
  @type version :: bytes4
  @type domain_type :: bytes4
  @type fork_digest :: bytes4
  @type domain :: bytes32
  @type bls_pubkey :: bytes48
  @type bls_signature :: bytes96
  @type participation_flags :: uint8
  # Max size: 2**30
  @type transaction :: binary
  @type execution_address :: bytes20
  @type withdrawal_index :: uint64
  @type payload_id :: bytes8
  @type blob_index :: uint64
  # Max size: BYTES_PER_FIELD_ELEMENT * FIELD_ELEMENTS_PER_BLOB
  @type blob :: binary
  @type kzg_commitment :: bytes48
  @type kzg_proof :: bytes48
end
