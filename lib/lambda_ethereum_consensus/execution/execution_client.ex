defmodule LambdaEthereumConsensus.Execution.ExecutionClient do
  @moduledoc """
  Execution Layer Engine API methods
  """
  alias LambdaEthereumConsensus.Execution.EngineApi
  alias LambdaEthereumConsensus.Execution.RPC
  alias LambdaEthereumConsensus.SszEx
  alias Types.BlobsBundle
  alias Types.DepositData
  alias Types.ExecutionPayload
  alias Types.NewPayloadRequest
  alias Types.Withdrawal

  require Logger

  @type execution_status :: :optimistic | :valid | :invalid | :unknown

  @spec get_payload(Types.payload_id()) ::
          {:error, {ExecutionPayload.t(), BlobsBundle.t()}} | {:ok, any()}
  def get_payload(payload_id) do
    case EngineApi.get_payload(payload_id) do
      {:ok, %{"execution_payload" => raw_payload, "blobs_bundle" => raw_blobs_bundle}} ->
        {:ok, {parse_raw_payload(raw_payload), parse_raw_blobs_bundle(raw_blobs_bundle)}}

      {:error, reason} ->
        Logger.error("Error when calling get payload: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Verifies the validity of the data contained in the new payload and notifies the Execution client of a new payload
  """
  @spec notify_new_payload(NewPayloadRequest.t()) ::
          {:ok, execution_status()} | {:error, String.t()}
  def notify_new_payload(%NewPayloadRequest{
        execution_payload: execution_payload,
        versioned_hashes: versioned_hashes,
        parent_beacon_block_root: parent_beacon_block_root
      }) do
    case EngineApi.new_payload(execution_payload, versioned_hashes, parent_beacon_block_root) do
      {:ok, %{"status" => status}} ->
        {:ok, parse_status(status)}

      {:error, reason} ->
        Logger.warning("Error when calling notify new payload: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def notify_forkchoice_updated(fork_choice_state) do
    case EngineApi.forkchoice_updated(fork_choice_state, nil) do
      {:ok, %{"payload_status" => %{"status" => status}}} ->
        {:ok, parse_status(status)}

      {:error, reason} ->
        Logger.warning("Error when calling notify forkchoice updated: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  This function sets in motion a payload build process on top of
  `head_block_hash` and returns an identifier of initiated process.
  """
  def notify_forkchoice_updated(fork_choice_state, payload_attributes) do
    case EngineApi.forkchoice_updated(fork_choice_state, payload_attributes) do
      {:ok, %{"payload_id" => nil, "payload_status" => %{"status" => status}}} ->
        {:error, "No payload id, status is #{parse_status(status)}"}

      {:ok, %{"payload_id" => payload_id, "payload_status" => %{"status" => "VALID"}}} ->
        {:ok, payload_id}

      {:error, reason} ->
        Logger.warning("Error when calling notify forkchoice updated: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Equivalent to `is_valid_block_hash` from the spec.
  Return ``true`` if and only if ``execution_payload.block_hash`` is computed correctly.
  """
  @spec valid_block_hash?(ExecutionPayload.t()) ::
          {:ok, execution_status()} | {:error, String.t()}
  # TODO: implement
  def valid_block_hash?(_execution_payload), do: {:ok, :valid}
  def valid_block_hash?(_execution_payload, _parent_beacon_block_root), do: {:ok, :valid}

  @doc """
  Return ``true`` if and only if the version hashes computed by the blob transactions of
  ``new_payload_request.execution_payload`` matches ``new_payload_request.version_hashes``.
  """
  @spec valid_versioned_hashes?(NewPayloadRequest.t()) ::
          {:ok, execution_status()} | {:error, String.t()}
  # TODO: implement
  def valid_versioned_hashes?(_new_payload_request), do: {:ok, :valid}

  @doc """
  Same as `notify_new_payload`, but with additional checks.
  """
  @spec verify_and_notify_new_payload(NewPayloadRequest.t()) ::
          {:ok, execution_status()} | {:error, String.t()}
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

  defp parse_raw_payload(raw_payload) do
    %{
      "baseFeePerGas" => raw_base_fee_per_gas,
      "blobGasUsed" => raw_blob_gas_used,
      "blockHash" => raw_block_hash,
      "blockNumber" => raw_block_number,
      "excessBlobGas" => raw_excess_blob_gas,
      "extraData" => raw_extra_data,
      "feeRecipient" => raw_fee_recipient,
      "gasLimit" => raw_gas_limit,
      "gasUsed" => raw_gas_used,
      "logsBloom" => raw_logs_bloom,
      "parentHash" => raw_parent_hash,
      "prevRandao" => raw_prev_randao,
      "receiptsRoot" => raw_receipts_root,
      "stateRoot" => raw_state_root,
      "timestamp" => raw_timestamp,
      "transactions" => raw_transactions,
      "withdrawals" => raw_withdrawals
    } = raw_payload

    %ExecutionPayload{
      base_fee_per_gas: raw_base_fee_per_gas |> RPC.decode_integer(),
      blob_gas_used: raw_blob_gas_used |> RPC.decode_integer(),
      block_hash: raw_block_hash |> RPC.decode_binary(),
      block_number: raw_block_number |> RPC.decode_integer(),
      excess_blob_gas: raw_excess_blob_gas |> RPC.decode_integer(),
      extra_data: raw_extra_data |> RPC.decode_binary(),
      fee_recipient: raw_fee_recipient |> RPC.decode_binary(),
      gas_limit: raw_gas_limit |> RPC.decode_integer(),
      gas_used: raw_gas_used |> RPC.decode_integer(),
      logs_bloom: raw_logs_bloom |> RPC.decode_binary(),
      parent_hash: raw_parent_hash |> RPC.decode_binary(),
      prev_randao: raw_prev_randao |> RPC.decode_binary(),
      receipts_root: raw_receipts_root |> RPC.decode_binary(),
      state_root: raw_state_root |> RPC.decode_binary(),
      timestamp: raw_timestamp |> RPC.decode_integer(),
      transactions: raw_transactions |> Enum.map(&RPC.decode_binary/1),
      # TODO: parse withdrawals
      withdrawals: raw_withdrawals |> Enum.map(&parse_withdrawal/1)
    }
  end

  defp parse_withdrawal(raw_withdrawal) do
    %Withdrawal{
      index: raw_withdrawal["index"] |> RPC.decode_integer(),
      validator_index: raw_withdrawal["validatorIndex"] |> RPC.decode_integer(),
      address: raw_withdrawal["address"] |> RPC.decode_binary(),
      amount: raw_withdrawal["amount"] |> RPC.decode_integer()
    }
  end

  defp parse_raw_blobs_bundle(%{
         "blobs" => raw_blobs,
         "commitments" => raw_commitments,
         "proofs" => raw_proofs
       }) do
    %BlobsBundle{
      blobs: raw_blobs |> Enum.map(&RPC.decode_binary/1),
      commitments: raw_commitments |> Enum.map(&RPC.decode_binary/1),
      proofs: raw_proofs |> Enum.map(&RPC.decode_binary/1)
    }
  end

  defp parse_status("SYNCING"), do: :optimistic
  defp parse_status("VALID"), do: :valid
  defp parse_status("INVALID"), do: :invalid
  defp parse_status(_status), do: :unknown
end
