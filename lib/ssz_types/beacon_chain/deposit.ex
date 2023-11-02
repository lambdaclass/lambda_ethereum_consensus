defmodule SszTypes.Deposit do
  @moduledoc """
  Struct definition for `Deposit`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :proof,
    :data
  ]

  @schema [
    %{proof: %{type: :list, schema: %{type: :bytes, size: 32}, max_size: 33, is_variable: false}},
    %{
      data: %{
        type: :container,
        schema: SszTypes.DepositData
      }
    }
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max size is 33
          proof: list(SszTypes.bytes32()),
          data: SszTypes.DepositData.t()
        }
  def schema, do: @schema
end
