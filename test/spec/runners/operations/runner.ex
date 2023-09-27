defmodule OperationsTestRunner do
  @moduledoc """
  Runner for Operations test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/operations
  """

  use ExUnit.CaseTemplate
  use TestRunner

  use ExUnit.CaseTemplate

  # Remove handler from here once you implement the corresponding functions
  # "deposit_receipt" handler is not yet implemented
  @disabled_handlers [
    "attestation",
    "attester_slashing",
    "block_header",
    "deposit",
    "proposer_slashing",
    "voluntary_exit",
    "sync_aggregate",
    # "execution_payload",
    "withdrawals",
    "bls_to_execution_change"
  ]

  def get_config("mainnet"), do: MainnetConfig
  def get_config("minimal"), do: MinimalConfig
  def get_config(_), do: raise("Unknown config")

  @doc """
  Returns true if the given testcase should be skipped
  """
  @impl TestRunner
  def skip?(%SpecTestCase{} = testcase) do
    Enum.member?(@disabled_handlers, testcase.handler)
  end

  @doc """
  Runs the given test case.
  """
  @impl TestRunner
  def run_test_case(%SpecTestCase{config: config} = testcase) do
    config = get_config(config)
    case_dir = SpecTestCase.dir(testcase)
    handler = testcase.handler

    {:ok, pre} = OperationsTestUtils.prepare_test(case_dir, handler, "pre", config)

    {:ok, operation} =
      OperationsTestUtils.prepare_test(
        case_dir,
        handler,
        OperationsTestUtils.resolve_name_from_handler(handler),
        config
      )

    {:ok, post} = OperationsTestUtils.prepare_test(case_dir, handler, "post", config)

    handle_case(testcase.handler, pre, operation, post, case_dir, config)
  end

  def handle_case("attestation", _pre, _operation, _post, _case_dir, _config) do
    # TODO
    assert false
  end

  def handle_case("attester_slashing", _pre, _operation, _post, _case_dir, _config) do
    # TODO
    assert false
  end

  def handle_case("block_header", _pre, _operation, _post, _case_dir, _config) do
    # TODO
    assert false
  end

  def handle_case("deposit", _pre, _operation, _post, _case_dir, _config) do
    # TODO
    assert false
  end

  def handle_case("proposer_slashing", _pre, _operation, _post, _case_dir, _config) do
    # TODO
    assert false
  end

  def handle_case("voluntary_exit", _pre, _operation, _post, _case_dir, _config) do
    # TODO
    assert false
  end

  def handle_case("sync_aggregate", _pre, _operation, _post, _case_dir, _config) do
    # TODO
    assert false
  end

  def handle_case("execution_payload", pre, operation, post, case_dir, config) do
    %{execution_valid: _execution_valid} =
      YamlElixir.read_from_file!(case_dir <> "/execution.yaml")
      |> SpecTestUtils.parse_yaml()

    if post == "no post" do
      {:ok, "no post"}
    else
      new_state =
        BeaconChain.StateTransition.process_execution_payload(
          pre,
          operation,
          config
        )

      if new_state == post, do: IO.puts("✅ new_state == post it matches baby!")

      assert new_state == post
    end
  end

  def handle_case("withdrawals", _pre, _operation, _post, _case_dir, _config) do
    # TODO
    assert false
  end

  def handle_case("bls_to_execution_change", _pre, _operation, _post, _case_dir, _config) do
    # TODO
    assert false
  end
end
