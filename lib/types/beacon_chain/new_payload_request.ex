defmodule NewPayloadRequest do
  @moduledoc """
  Struct received by `ExecutionClient.verify_and_notify_new_payload`.
  """
  fields = [:execution_payload]
  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          execution_payload: ExecutionPayload.t()
        }
end
