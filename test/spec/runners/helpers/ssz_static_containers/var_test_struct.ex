defmodule Helpers.SszStaticContainers.VarTestStruct do
  @moduledoc """
  Struct definition for `VarTestStruct`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :A,
    :B,
    :C
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          A: Types.uint16(),
          B: list(Types.uint16()),
          C: Types.uint8()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:A, {:int, 16}},
      {:B, {:list, {:int, 16}, 1024}},
      {:C, {:int, 8}}
    ]
  end
end
