defmodule BlsTestRunner do
  @moduledoc """
  Runner for BLS test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/bls
  """

  use ExUnit.CaseTemplate
  use TestRunner

  # Remove handler from here once you implement the corresponding functions
  @disabled_handlers [
    # "sign",
    # "verify",
    # "aggregate",
    # "fast_aggregate_verify",
    # "aggregate_verify",
    # "eth_aggregate_pubkeys"
    # "eth_fast_aggregate_verify"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{} = testcase) do
    Enum.member?(@disabled_handlers, testcase.handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    %{input: input, output: output} =
      YamlElixir.read_from_file!(case_dir <> "/data.yaml")
      |> SpecTestUtils.sanitize_yaml()

    handle_case(testcase.handler, input, output)
  end

  defp handle_case("sign", %{message: message, privkey: private_key}, output) do
    case output do
      nil ->
        assert {result, _error_msg} = Bls.sign(private_key, message)
        assert result == :error

      output ->
        assert {:ok, signature} = Bls.sign(private_key, message)
        assert signature == output
    end
  end

  defp handle_case("aggregate", signatures, output) do
    case output do
      nil ->
        assert {result, _error_msg} = Bls.aggregate(signatures)
        assert result == :error

      output ->
        assert {:ok, signature} = Bls.aggregate(signatures)
        assert signature == output
    end
  end

  defp handle_case("eth_aggregate_pubkeys", pubkeys, output) do
    case output do
      nil ->
        assert {result, _error_msg} = Bls.eth_aggregate_pubkeys(pubkeys)
        assert result == :error

      output ->
        assert {:ok, agg_pubkey} = Bls.eth_aggregate_pubkeys(pubkeys)
        assert agg_pubkey == output
    end
  end

  defp handle_case(
         "fast_aggregate_verify",
         %{message: message, pubkeys: pubkeys, signature: signature},
         output
       ) do
    case Bls.fast_aggregate_verify(pubkeys, message, signature) do
      {:ok, true} ->
        assert output

      {:ok, false} ->
        assert not output

      {:error, reason} ->
        assert not output, reason
    end
  end

  defp handle_case(
         "aggregate_verify",
         %{messages: messages, pubkeys: pubkeys, signature: signature},
         output
       ) do
    case Bls.aggregate_verify(pubkeys, messages, signature) do
      {:ok, true} ->
        assert output

      {:ok, false} ->
        assert not output

      {:error, reason} ->
        assert not output, reason
    end
  end

  defp handle_case(
         "verify",
         %{message: message, pubkey: pubkey, signature: signature},
         output
       ) do
    case Bls.verify(pubkey, message, signature) do
      {:ok, true} ->
        assert output

      {:ok, false} ->
        assert not output

      {:error, reason} ->
        assert not output, reason
    end
  end

  defp handle_case(
         "eth_fast_aggregate_verify",
         %{message: message, pubkeys: pubkeys, signature: signature},
         output
       ) do
    case Bls.eth_fast_aggregate_verify(pubkeys, message, signature) do
      {:ok, true} ->
        assert output

      {:ok, false} ->
        assert not output

      {:error, reason} ->
        assert not output, reason
    end
  end
end
