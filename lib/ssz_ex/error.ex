defmodule SszEx.Error do
  @moduledoc """
  Error messages for SszEx domain.
  """
  alias SszEx.Error
  defstruct [:message, stacktrace: []]
  @type t :: %__MODULE__{message: String.t(), stacktrace: list()}

  def format(%Error{message: message, stacktrace: []}), do: "#{message}"

  def format(%Error{message: message, stacktrace: stacktrace}) do
    "#{message}"
    formatted_stacktrace = stacktrace |> Enum.join(".")
    "#{message}Stacktrace: #{formatted_stacktrace}"
  end

  def add_container(%Error{message: message, stacktrace: stacktrace}, value)
      when is_struct(value) do
    new_trace =
      value.__struct__ |> Module.split() |> List.last()

    %Error{message: message, stacktrace: [new_trace | stacktrace]}
  end

  def add_container(%Error{message: message, stacktrace: stacktrace}, value) do
    new_trace =
      value |> Module.split() |> List.last()

    %Error{message: message, stacktrace: [new_trace | stacktrace]}
  end

  def add_container({:error, %Error{} = error}, new_trace),
    do: {:error, Error.add_container(error, new_trace)}

  def add_container(value, _module), do: value

  def add_trace(%Error{message: message, stacktrace: stacktrace}, new_trace) do
    %Error{message: message, stacktrace: [new_trace | stacktrace]}
  end

  def add_trace({:error, %Error{} = error}, new_trace),
    do: {:error, Error.add_trace(error, new_trace)}

  def add_trace(value, _module), do: value

  defimpl String.Chars, for: __MODULE__ do
    def to_string(error), do: Error.format(error)
  end
end
