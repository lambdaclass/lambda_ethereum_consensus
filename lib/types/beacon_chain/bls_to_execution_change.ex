defmodule Types.BLSToExecutionChange do
  @moduledoc """
  Struct definition for `BLSToExecutionChange`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :validator_index,
    :from_bls_pubkey,
    :to_execution_address
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          validator_index: Types.validator_index(),
          from_bls_pubkey: Types.bls_pubkey(),
          to_execution_address: Types.execution_address()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:validator_index, {:int, 64}},
      {:from_bls_pubkey, {:bytes, 48}},
      {:to_execution_address, {:bytes, 20}}
    ]
  end
end
