defmodule Types.SyncAggregate do
  @moduledoc """
  Struct definition for `SyncAggregate`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :sync_committee_bits,
    :sync_committee_signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          sync_committee_bits: Types.bitvector(),
          sync_committee_signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:sync_committee_bits, {:bitvector, 512}},
      {:sync_committee_signature, {:bytes, 96}}
    ]
  end
end
