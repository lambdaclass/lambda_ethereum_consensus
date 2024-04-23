defmodule Types.ForkData do
  @moduledoc """
  Struct definition for `ForkData`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  use LambdaEthereumConsensus.Container

  fields = [
    :current_version,
    :genesis_validators_root
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          current_version: Types.version(),
          genesis_validators_root: Types.root()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:current_version, TypeAliases.version()},
      {:genesis_validators_root, TypeAliases.root()}
    ]
  end
end
