defmodule SszTypes.Transaction do
  @moduledoc """
  Alias for `SszTypes.transaction`. Is used when explicit typing is needed.
  """
  # MAX_BYTES_PER_TRANSACTION
  @schema %{type: :list, schema: %{type: :bytes}, max_size: 1_073_741_824}
  def schema, do: @schema
end
