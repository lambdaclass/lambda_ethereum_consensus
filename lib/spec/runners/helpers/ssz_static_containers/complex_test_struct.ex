defmodule Helpers.SszStaticContainers.ComplexTestStruct do
  @moduledoc """
  Struct definition for `ComplexTestStruct`.
  """
  alias Helpers.SszStaticContainers.FixedTestStruct
  alias Helpers.SszStaticContainers.VarTestStruct
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :A,
    :B,
    :C,
    :D,
    :E,
    :F,
    :G
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          A: SszTypes.uint16(),
          B: list(SszTypes.uint16()),
          C: SszTypes.uint8(),
          D: SszTypes.bitlist(),
          E: VarTestStruct,
          F: list(FixedTestStruct),
          G: list(VarTestStruct)
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:A, {:int, 16}},
      {:B, {:list, {:int, 16}, 1024}},
      {:C, {:int, 8}},
      {:D, {:bitlist, 256}},
      {:E, VarTestStruct},
      {:F, {:vector, FixedTestStruct, 4}},
      {:G, {:vector, VarTestStruct, 2}}
    ]
  end
end
