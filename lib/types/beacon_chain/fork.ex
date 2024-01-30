defmodule Types.Fork do
  @moduledoc """
  Struct definition for `Fork`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :previous_version,
    :current_version,
    :epoch
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          previous_version: Types.version(),
          current_version: Types.version(),
          epoch: Types.epoch()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:previous_version, TypeAliases.version()},
      {:current_version, TypeAliases.version()},
      {:epoch, TypeAliases.epoch()}
    ]
  end
end
