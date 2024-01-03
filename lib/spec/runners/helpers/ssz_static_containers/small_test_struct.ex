defmodule Helpers.SszStaticContainers.SmallTestStruct do
  @moduledoc """
  Struct definition for `SmallTestStruct`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :A,
    :B
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          A: Types.uint16(),
          B: Types.uint16()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:A, {:int, 16}},
      {:B, {:int, 16}}
    ]
  end
end
