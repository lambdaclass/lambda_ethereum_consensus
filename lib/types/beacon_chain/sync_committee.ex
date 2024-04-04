defmodule Types.SyncCommittee do
  @moduledoc """
  Struct definition for `SyncCommittee`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  use LambdaEthereumConsensus.Container

  fields = [
    :pubkeys,
    :aggregate_pubkey
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max size SYNC_COMMITTEE_SIZE
          pubkeys: list(Types.bls_pubkey()),
          aggregate_pubkey: Types.bls_pubkey()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:pubkeys, {:vector, TypeAliases.bls_pubkey(), ChainSpec.get("SYNC_COMMITTEE_SIZE")}},
      {:aggregate_pubkey, TypeAliases.bls_pubkey()}
    ]
  end
end
