defmodule LambdaEthereumConsensus.Execution.ExecutionClient do
  @moduledoc """
  Execution Layer Engine API methods
  """
  alias LambdaEthereumConsensus.Execution.EngineApi
  alias Types.ExecutionPayload
  alias Types.NewPayloadRequest
  require Logger

  use HardForkAliasInjection

  @doc """
  Verifies the validity of the data contained in the new payload and notifies the Execution client of a new payload
  """
  @spec notify_new_payload(ExecutionPayload.t()) ::
          {:ok, :optimistic | :valid | :invalid} | {:error, String.t()}
  def notify_new_payload(execution_payload) do
    result = EngineApi.new_payload(execution_payload)

    case result do
      {:ok, %{"status" => "SYNCING"}} ->
        {:ok, :optimistic}

      {:ok, %{"status" => "VALID"}} ->
        {:ok, :valid}

      {:ok, %{"status" => "INVALID"}} ->
        {:ok, :invalid}

      {:error, error} ->
        {:error, error}
    end
  end

  # TODO: implement
  def notify_new_payload(_execution_payload, _parent_beacon_block_root), do: {:ok, :valid}

  @doc """
  This function performs three actions *atomically*:
  * Re-organizes the execution payload chain and corresponding state to make `head_block_hash` the head.
  * Updates safe block hash with the value provided by `safe_block_hash` parameter.
  * Applies finality to the execution state: it irreversibly persists the chain of all execution payloads
  and corresponding state, up to and including `finalized_block_hash`.

  Additionally, if `payload_attributes` is provided, this function sets in motion a payload build process on top of
  `head_block_hash` and returns an identifier of initiated process.

  """
  @spec notify_forkchoice_updated(Types.hash32(), Types.hash32(), Types.hash32()) ::
          {:ok, any} | {:error, any}
  def notify_forkchoice_updated(head_block_hash, safe_block_hash, finalized_block_hash) do
    fork_choice_state = %{
      finalized_block_hash: finalized_block_hash,
      head_block_hash: head_block_hash,
      safe_block_hash: safe_block_hash
    }

    EngineApi.forkchoice_updated(fork_choice_state, nil)
  end

  @doc """
  Equivalent to is_valid_block_hash from the spec.
  Return ``true`` if and only if ``execution_payload.block_hash`` is computed correctly.
  """
  @spec valid_block_hash?(ExecutionPayload.t()) ::
          {:ok, :optimistic | :valid | :invalid} | {:error, String.t()}
  # TODO: implement
  def valid_block_hash?(_execution_payload), do: {:ok, :valid}
  def valid_block_hash?(_execution_payload, _parent_beacon_block_root), do: {:ok, :valid}

  @doc """
  Return ``true`` if and only if the version hashes computed by the blob transactions of
  ``new_payload_request.execution_payload`` matches ``new_payload_request.version_hashes``.
  """
  @spec valid_versioned_hashes?(ExecutionPayload.t()) ::
          {:ok, :optimistic | :valid | :invalid} | {:error, String.t()}
  # TODO: implement
  def valid_versioned_hashes?(_new_payload_request), do: {:ok, :valid}

  @doc """
  Same as `notify_new_payload`, but with additional checks.
  """
  # CAPELLA
  def verify_and_notify_new_payload(%NewPayloadRequest{
        execution_payload: execution_payload,
        parent_beacon_block_root: nil,
        versioned_hashes: nil
      }) do
    with {:ok, :valid} <- valid_block_hash?(execution_payload) do
      notify_new_payload(execution_payload)
    end
  end

  # DENEB
  @spec verify_and_notify_new_payload(NewPayloadRequest.t()) ::
          {:ok, :optimistic | :valid | :invalid} | {:error, String.t()}
  def verify_and_notify_new_payload(
        %NewPayloadRequest{
          execution_payload: execution_payload,
          parent_beacon_block_root: parent_beacon_block_root
        } = new_payload_request
      ) do
    with {:ok, :valid} <- valid_block_hash?(execution_payload, parent_beacon_block_root),
         {:ok, :valid} <- valid_versioned_hashes?(new_payload_request) do
      notify_new_payload(execution_payload, parent_beacon_block_root)
    end
  end
end
