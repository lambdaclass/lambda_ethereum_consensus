defmodule SszTypes.PendingAttestation do
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
          aggregation_bits: SszTypes.bitlist(),
          data: SszTypes.AttestationData.t(),
          inclusion_delay: SszTypes.slot(),
          proposer_index: SszTypes.validator_index()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:aggregation_bits, {:bitlist, 2048}},
      {:data, SszTypes.AttestationData},
      {:inclusion_delay, {:int, 64}},
      {:proposer_index, {:int, 64}}
    ]
  end
end
