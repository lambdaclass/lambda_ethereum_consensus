defmodule Types.Checkpoint do
  @moduledoc """
  Struct definition for `Checkpoint`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  use LambdaEthereumConsensus.Container

  fields = [
    :root,
    :epoch
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          epoch: Types.epoch(),
          root: Types.root()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:epoch, TypeAliases.epoch()},
      {:root, TypeAliases.root()}
    ]
  end
end
