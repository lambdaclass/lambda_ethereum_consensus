defmodule Helpers.SszStaticContainers.SingleFieldTestStruct do
  @moduledoc """
  Struct definition for `SingleFieldTestStruct`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :A
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          A: SszTypes.uint8()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:A, {:int, 8}}
    ]
  end
end
