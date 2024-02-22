defmodule Types.SyncAggregate do
  @moduledoc """
  Struct definition for `SyncAggregate`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  alias LambdaEthereumConsensus.Utils.BitVector

  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :sync_committee_bits,
    :sync_committee_signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max size SYNC_COMMITTEE_SIZE
          sync_committee_bits: BitVector.t(),
          sync_committee_signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:sync_committee_bits, {:bitvector, ChainSpec.get("SYNC_COMMITTEE_SIZE")}},
      {:sync_committee_signature, TypeAliases.bls_signature()}
    ]
  end

  def encode(%__MODULE__{} = map) do
    Map.update!(map, :sync_committee_bits, &BitVector.to_bytes/1)
  end

  def decode(%__MODULE__{} = map) do
    Map.update!(map, :sync_committee_bits, fn bits ->
      BitVector.new(bits, ChainSpec.get("SYNC_COMMITTEE_SIZE"))
    end)
  end
end
