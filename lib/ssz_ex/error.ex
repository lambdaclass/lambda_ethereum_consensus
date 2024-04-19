defmodule SszEx.Error do
  @moduledoc """
  Error messages for SszEx domain.
  """
  alias SszEx.Error
  defstruct [:message]
  @type t :: %__MODULE__{message: binary()}

  def format(%Error{message: message}) do
    "#{message}"
  end

  defimpl String.Chars, for: __MODULE__ do
    def to_string(error), do: Error.format(error)
  end
end
