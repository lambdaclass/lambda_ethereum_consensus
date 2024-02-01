defmodule Types.BlockMetadata do
  @moduledoc """
    Block metadata that is stored in the database.
  """

  fields = [
    :status,
    :execution_status
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          status: :valid | :invalid | :unknown,
          execution_status: :optimistic | :valid | :invalid | :unknown
        }

  @spec default() :: t()
  def default do
    %__MODULE__{
      status: :unknown,
      execution_status: :unknown
    }
  end

  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{} = block_metadata) do
    :erlang.term_to_binary(block_metadata)
  end

  @spec deserialize(binary()) :: t()
  def deserialize(binary) do
    :erlang.binary_to_term(binary)
  end
end
