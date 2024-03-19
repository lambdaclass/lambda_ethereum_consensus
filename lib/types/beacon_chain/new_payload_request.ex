defmodule Types.NewPayloadRequest do
  @moduledoc """
  Struct received by `ExecutionClient.verify_and_notify_new_payload`.
  """
  alias Types.ExecutionPayload

  @enforce_keys [:execution_payload]
  defstruct [:execution_payload, :versioned_hashes, :parent_beacon_block_root]

  @type t :: %__MODULE__{
          execution_payload: ExecutionPayload.t(),
          versioned_hashes: list(Types.bytes32()) | nil,
          parent_beacon_block_root: Types.root() | nil
        }
end
