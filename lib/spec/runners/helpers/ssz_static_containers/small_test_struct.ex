defmodule Helpers.SszStaticContainers.SmallTestStruct do
  @moduledoc """
  Struct definition for `SmallTestStruct`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :A,
    :B
  ]

  @type uint16 :: 0..unquote(2 ** 16 - 1)

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          A: uint16(),
          B: uint16()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:A, {:int, 16}},
      {:B, {:int, 16}}
    ]
  end
end
