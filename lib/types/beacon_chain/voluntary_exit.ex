defmodule Types.VoluntaryExit do
  @moduledoc """
  Struct definition for `VoluntaryExit`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :epoch,
    :validator_index
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          epoch: Types.epoch(),
          validator_index: Types.validator_index()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:epoch, TypeAliases.epoch()},
      {:validator_index, TypeAliases.validator_index()}
    ]
  end
end
