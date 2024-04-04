defmodule LambdaEthereumConsensus.Execution.ExecutionClient do
  @moduledoc """
  Execution Layer Engine API methods
  """
  alias LambdaEthereumConsensus.Execution.EngineApi
  alias LambdaEthereumConsensus.SszEx
  alias Types.DepositData
  alias Types.ExecutionPayload
  alias Types.NewPayloadRequest
  require Logger

  @doc """
  Verifies the validity of the data contained in the new payload and notifies the Execution client of a new payload
  """
  @spec notify_new_payload(NewPayloadRequest.t()) ::
          {:ok, :optimistic | :valid | :invalid} | {:error, String.t()}
  def notify_new_payload(%NewPayloadRequest{
        execution_payload: execution_payload,
        versioned_hashes: versioned_hashes,
        parent_beacon_block_root: parent_beacon_block_root
      }) do
    EngineApi.new_payload(execution_payload, versioned_hashes, parent_beacon_block_root)
    |> parse_rpc_result()
  end

  defp parse_rpc_result({:ok, %{"status" => "SYNCING"}}), do: {:ok, :optimistic}
  defp parse_rpc_result({:ok, %{"status" => "VALID"}}), do: {:ok, :valid}
  defp parse_rpc_result({:ok, %{"status" => "INVALID"}}), do: {:ok, :invalid}
  defp parse_rpc_result({:error, _} = err), do: err

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
  Equivalent to `is_valid_block_hash` from the spec.
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
  @spec valid_versioned_hashes?(NewPayloadRequest.t()) ::
          {:ok, :optimistic | :valid | :invalid} | {:error, String.t()}
  # TODO: implement
  def valid_versioned_hashes?(_new_payload_request), do: {:ok, :valid}

  @doc """
  Same as `notify_new_payload`, but with additional checks.
  """
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
      notify_new_payload(new_payload_request)
    end
  end

  @type block_metadata :: %{
          block_hash: Types.root(),
          block_number: Types.uint64(),
          timestamp: Types.uint64()
        }

  @spec get_block_metadata(nil | Types.uint64() | Types.root()) ::
          {:ok, block_metadata() | nil} | {:error, any}
  def get_block_metadata(block_id) do
    with {:ok, block} <- EngineApi.get_block_header(block_id) do
      parse_block_metadata(block)
    end
  end

  @type deposit_log :: %{
          data: DepositData.t(),
          block_number: Types.uint64(),
          index: Types.uint64()
        }

  @spec get_deposit_logs(Range.t()) :: {:ok, [deposit_log()]} | {:error, any}
  def get_deposit_logs(block_range) do
    with {:ok, raw_logs} <- EngineApi.get_deposit_logs(block_range) do
      parse_raw_logs(raw_logs)
    end
  end

  defp parse_block_metadata(nil), do: {:ok, nil}

  defp parse_block_metadata(%{
         "hash" => "0x" <> hash,
         "number" => "0x" <> number,
         "timestamp" => "0x" <> timestamp
       }) do
    parsed_number = String.to_integer(number, 16)
    parsed_timestamp = String.to_integer(timestamp, 16)

    case Base.decode16(hash, case: :mixed) do
      {:ok, parsed_hash} ->
        {:ok,
         %{block_hash: parsed_hash, block_number: parsed_number, timestamp: parsed_timestamp}}

      :error ->
        {:error, "invalid block hash"}
    end
  end

  defp parse_block_metadata(_), do: {:error, "invalid block format"}

  defp parse_raw_logs(raw_logs) do
    {:ok, Enum.map(raw_logs, &parse_raw_log/1)}
  end

  @min_hex_data_byte_size 1104

  defp parse_raw_log(%{"data" => "0x" <> hex_data, "blockNumber" => "0x" <> hex_block_number})
       when byte_size(hex_data) >= @min_hex_data_byte_size do
    # TODO: we might want to move this parsing behind the EngineApi module (and maybe rename it).
    data = Base.decode16!(hex_data, case: :mixed)

    # These magic numbers correspond to the start and length of each field in the deposit log data.
    pubkey = binary_part(data, 192, 48)
    withdrawal_credentials = binary_part(data, 288, 32)
    {:ok, amount} = binary_part(data, 352, 8) |> SszEx.decode(TypeAliases.uint64())
    signature = binary_part(data, 416, 96)
    {:ok, index} = binary_part(data, 544, 8) |> SszEx.decode(TypeAliases.uint64())

    block_number = String.to_integer(hex_block_number, 16)

    deposit_data = %DepositData{
      pubkey: pubkey,
      withdrawal_credentials: withdrawal_credentials,
      amount: amount,
      signature: signature
    }

    %{data: deposit_data, block_number: block_number, index: index}
  end
end
