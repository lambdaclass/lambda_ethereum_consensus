defmodule Helpers.SszStaticContainers.BitsStruct do
  @moduledoc """
  Struct definition for `BitsStruct`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :A,
    :B,
    :C,
    :D,
    :E
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          A: Types.bitlist(),
          B: Types.bitvector(),
          C: Types.bitvector(),
          D: Types.bitlist(),
          E: Types.bitvector()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:A, {:bitlist, 5}},
      {:B, {:bitvector, 2}},
      {:C, {:bitvector, 1}},
      {:D, {:bitlist, 6}},
      {:E, {:bitvector, 8}}
    ]
  end
end
