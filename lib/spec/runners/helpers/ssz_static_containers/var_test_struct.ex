defmodule Helpers.SszStaticContainers.VarTestStruct do
  @moduledoc """
  Struct definition for `VarTestStruct`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :A,
    :B,
    :C
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          A: SszTypes.uint16(),
          B: list(SszTypes.uint16()),
          C: SszTypes.uint8()
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
