defmodule SszEx.Error do
  @moduledoc """
  Error messages for SszEx domain.
  """
  alias SszEx.Error
  defstruct [:message, :stacktrace]
  @type t :: %__MODULE__{message: String.t(), stacktrace: list()}

  def format(%Error{message: message, stacktrace: nil}), do: "#{message}"

  def format(%Error{message: message, stacktrace: stacktrace}) do
    "#{message}"
    formatted_stacktrace = stacktrace |> Enum.join(".")
    "#{message}Stacktrace: #{formatted_stacktrace}"
  end

  def add_trace(%Error{message: message, stacktrace: nil}, new_trace) do
    %Error{message: message, stacktrace: [new_trace]}
  end

  def add_trace(%Error{message: message, stacktrace: stacktrace}, new_trace) do
    %Error{message: message, stacktrace: [new_trace | stacktrace]}
  end

  def add_trace({:error, %Error{} = error}, module),
    do: {:error, Error.add_trace(error, module)}

  def add_trace(value, _module), do: value

  defimpl String.Chars, for: __MODULE__ do
    def to_string(error), do: Error.format(error)
  end
end
