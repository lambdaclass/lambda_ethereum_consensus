defmodule Helpers.SszStaticContainers.SingleFieldTestStruct do
  @moduledoc """
  Struct definition for `SingleFieldTestStruct`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :A
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          A: Types.uint8()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:A, {:int, 8}}
    ]
  end
end
