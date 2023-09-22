defmodule OperationsTestAssert do
  @moduledoc """
  Assertions for the Operations test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/operations
  """
  use ExUnit.Case

  def assert_process_attestation(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_attester_slashing(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_block_header(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_deposit(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_proposer_slashing(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_voluntary_exit(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_sync_aggregate(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_execution_payload(pre, operation, _post, data, config) do
    with {:ok, processed_payload} <-
           OperationsTestFunctions.test_process_execution_payload(pre, operation, data, config),
         {:ok, ssz_state} <- Ssz.to_ssz_typed(processed_payload, SszTypes.BeaconState, config) do
      :snappyer.compress(ssz_state)
    end
  end

  def assert_process_withdrawal(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_bls_to_execution_change(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end
end
