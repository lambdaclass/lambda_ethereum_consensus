defmodule SszTypes.Fork do
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
          previous_version: SszTypes.version(),
          current_version: SszTypes.version(),
          epoch: SszTypes.epoch()
        }

  def schema do
    [
      {:previous_version, {:int, 4}},
      {:current_version, {:int, 4}},
      {:epoch, {:int, 64}}
    ]
  end
end
