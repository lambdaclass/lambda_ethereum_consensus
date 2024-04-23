defmodule Types.BLSToExecutionChange do
  @moduledoc """
  Struct definition for `BLSToExecutionChange`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

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
  def schema() do
    [
      {:validator_index, TypeAliases.validator_index()},
      {:from_bls_pubkey, TypeAliases.bls_pubkey()},
      {:to_execution_address, TypeAliases.execution_address()}
    ]
  end
end
