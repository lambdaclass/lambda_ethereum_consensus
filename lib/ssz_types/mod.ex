defmodule SszTypes do
  @moduledoc """
  Lists some types used in SSZ structs.
  """

  # Primitive types
  ## Integer types
  @type uint8 :: 0..unquote(2 ** 8 - 1)
  @type uint64 :: 0..unquote(2 ** 64 - 1)
  @type uint256 :: 0..unquote(2 ** 256 - 1)

  ## Binary types
  @type bytes4 :: <<_::32>>
  @type bytes20 :: <<_::160>>
  @type bytes32 :: <<_::256>>
  @type bytes48 :: <<_::384>>
  @type bytes96 :: <<_::768>>

  # bitlists are stored in SSZ format
  @type bitlist :: binary()
  @type bitvector :: binary()

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
  @type participation_flags :: uint8()
  @type transaction :: list()
  @type execution_address :: bytes20()
  @type withdrawal_index :: uint64()
end
