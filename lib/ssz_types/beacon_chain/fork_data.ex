defmodule SszTypes.ForkData do
  @moduledoc """
  Struct definition for `ForkData`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :current_version,
    :genesis_validators_root
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          current_version: SszTypes.version(),
          genesis_validators_root: SszTypes.root()
        }

  def schema do
    [
      {:current_version, {:int, 4}},
      {:genesis_validators_root, {:bytes, 32}}
    ]
  end
end
