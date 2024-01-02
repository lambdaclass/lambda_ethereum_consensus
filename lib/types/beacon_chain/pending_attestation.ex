defmodule Types.PendingAttestation do
  @moduledoc """
  Struct definition for `PendingAttestation`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :aggregation_bits,
    :data,
    :inclusion_delay,
    :proposer_index
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max size is MAX_VALIDATORS_PER_COMMITTEE
          aggregation_bits: Types.bitlist(),
          data: Types.AttestationData.t(),
          inclusion_delay: Types.slot(),
          proposer_index: Types.validator_index()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:aggregation_bits, {:bitlist, ChainSpec.get("MAX_VALIDATORS_PER_COMMITTEE")}},
      {:data, Types.AttestationData},
      {:inclusion_delay, {:int, 64}},
      {:proposer_index, {:int, 64}}
    ]
  end
end
