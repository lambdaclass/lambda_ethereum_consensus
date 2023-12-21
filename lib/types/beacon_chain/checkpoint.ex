defmodule Types.Checkpoint do
  @moduledoc """
  Struct definition for `Checkpoint`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  @behaviour LambdaEthereumConsensus.Container
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

  def schema do
    [
      {:epoch, {:int, 64}},
      {:root, {:bytes, 32}}
    ]
  end
end
