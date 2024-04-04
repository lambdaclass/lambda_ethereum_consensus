defmodule Helpers.SszStaticContainers.ComplexTestStruct do
  @moduledoc """
  Struct definition for `ComplexTestStruct`.
  """
  alias Helpers.SszStaticContainers.FixedTestStruct
  alias Helpers.SszStaticContainers.VarTestStruct
  use LambdaEthereumConsensus.Container

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
          A: Types.uint16(),
          B: list(Types.uint16()),
          C: Types.uint8(),
          D: list(Types.uint8()),
          E: VarTestStruct,
          F: list(FixedTestStruct),
          G: list(VarTestStruct)
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:A, {:int, 16}},
      {:B, {:list, {:int, 16}, 128}},
      {:C, {:int, 8}},
      {:D, {:list, {:int, 8}, 256}},
      {:E, VarTestStruct},
      {:F, {:vector, FixedTestStruct, 4}},
      {:G, {:vector, VarTestStruct, 2}}
    ]
  end
end
