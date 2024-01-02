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
          # max size is 2048
          aggregation_bits: Types.bitlist(),
          data: Types.AttestationData.t(),
          inclusion_delay: Types.slot(),
          proposer_index: Types.validator_index()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:aggregation_bits, {:bitlist, 2048}},
      {:data, Types.AttestationData},
      {:inclusion_delay, {:int, 64}},
      {:proposer_index, {:int, 64}}
    ]
  end
end
