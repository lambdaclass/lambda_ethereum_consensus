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

  @type uint16 :: 0..unquote(2 ** 16 - 1)

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          A: uint16(),
          B: list(uint16()),
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
