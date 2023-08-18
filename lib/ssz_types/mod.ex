defmodule SszTypes do
  @moduledoc """
  Lists some types used in SSZ structs.
  """

  # Primitive types
  ## Integer types
  @type uint64 :: 0..unquote(2 ** 64 - 1)

  ## Binary types
  @type bytes4 :: <<_::32>>
  @type bytes32 :: <<_::256>>
  @type bytes48 :: <<_::384>>
  @type bytes96 :: <<_::768>>

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
end
