defmodule OperationsTestUtils do
  @moduledoc """
  Utils for the Operations test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/operations
  """

  # Map the operation-name to the associated operation-type
  @type_map %{
    "attestation" => "Attestation",
    "attester_slashing" => "AttesterSlashing",
    "block_header" => "BeaconBlock",
    "deposit" => "Deposit",
    "proposer_slashing" => "ProposerSlashing",
    "voluntary_exit" => "SignedVoluntaryExit",
    "sync_aggregate" => "SyncAggregate",
    "execution_payload" => "ExecutionPayload",
    "withdrawals" => "ExecutionPayload",
    "bls_to_execution_change" => "SignedBLSToExecutionChange"
    # "deposit_receipt" => "DepositReceipt" Not yet implemented
  }

  # Map the operation-name to the associated input name
  @name_map %{
    "attestation" => "attestation",
    "attester_slashing" => "attester_slashing",
    "block_header" => "block",
    "deposit" => "deposit",
    "proposer_slashing" => "proposer_slashing",
    "voluntary_exit" => "voluntary_exit",
    "sync_aggregate" => "sync_aggregate",
    "execution_payload" => "execution_payload",
    "withdrawals" => "execution_payload",
    "bls_to_execution_change" => "address_change"
    # "deposit_receipt" => "deposit_receipt" Not yet implemented
  }

  # Local test config
  @config MinimalConfig

  @doc """
  Prepares the data for the tests: build_path() |> decompress() |> deserialize()
  """
  def prepare_test(case_dir, handler, name) do
    build_file_path(case_dir, name) |> decompress() |> deserialize(handler, name)
  end

  @doc """
  Snappy decompression of the files
  """
  def decompress(file_path) do
    if File.exists?(file_path) do
      compressed = File.read!(file_path)
      {:ok, decompressed} = :snappyer.decompress(compressed)
      {:ok, decompressed}
    else
      {:ok, "no post"}
    end
  end

  @doc """
  Deserialization of the files
  """
  def deserialize({:ok, "no post"}, _, _), do: {:ok, "no post"}

  def deserialize({:ok, serialized}, _handler, "pre") do
    Ssz.from_ssz(serialized, SszTypes.BeaconState, @config)
  end

  def deserialize({:ok, serialized}, _handler, "post") do
    Ssz.from_ssz(serialized, SszTypes.BeaconState, @config)
  end

  def deserialize({:ok, serialized}, handler, _) do
    Ssz.from_ssz(serialized, resolve_type_from_handler(handler), @config)
  end

  def build_file_path(case_dir, name) do
    "#{case_dir}/#{name}.ssz_snappy"
  end

  @doc """
  Each handler has associated types, hence we resolve each type that has to be used from each handler
  """
  def resolve_type_from_handler(handler) do
    case Map.get(@type_map, handler) do
      nil -> raise "Unknown case #{handler}"
      type -> Module.concat(SszTypes, type)
    end
  end

  @doc """
  Each handler has associated name, hence we resolve each name that has to be used from each handler
  """
  def resolve_name_from_handler(handler) do
    case Map.get(@name_map, handler) do
      nil -> raise "Unknown case #{handler}"
      name -> name
    end
  end
end
