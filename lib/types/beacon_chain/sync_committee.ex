defmodule Types.SyncCommittee do
  @moduledoc """
  Struct definition for `SyncCommittee`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  @behaviour LambdaEthereumConsensus.Container

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
      {:pubkeys, {:list, {:bytes, 48}, ChainSpec.get("SYNC_COMMITTEE_SIZE")}},
      {:aggregate_pubkey, {:bytes, 48}}
    ]
  end
end
