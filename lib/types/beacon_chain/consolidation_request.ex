defmodule Types.ConsolidationRequest do
  @moduledoc """
  Struct definition for `ConsolidationRequest`.
  Added in Electra fork (EIP7251).
  """

  use LambdaEthereumConsensus.Container

  fields = [:source_address, :source_pubkey, :target_pubkey]
  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          source_address: Types.execution_address(),
          source_pubkey: Types.bls_pubkey(),
          target_pubkey: Types.bls_pubkey()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:source_address, TypeAliases.execution_address()},
      {:source_pubkey, TypeAliases.bls_pubkey()},
      {:target_pubkey, TypeAliases.bls_pubkey()}
    ]
  end
end
