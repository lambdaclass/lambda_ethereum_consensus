defmodule BLSTestRunner do
  use ExUnit.CaseTemplate
  # use TestRunner

  @moduledoc """
  Runner for BLS test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/bls
  """

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
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    %{input: input, output: output} =
      YamlElixir.read_from_file!(case_dir <> "/data.yaml")
      |> SpecTestUtils.parse_yaml()

    case testcase.handler do
      "sign" ->
        assert_sign(input, output)

      "verify" ->
        assert_verify(input, output)

      "aggregate" ->
        assert_aggregate(input, output)

      "fast_aggregate_verify" ->
        assert_fast_aggregate_verify(input, output)

      "aggregate_verify" ->
        assert_aggregate_verify(input, output)

      "eth_aggregate_pubkeys" ->
        assert_eth_aggregate_pubkeys(input, output)

      "eth_fast_aggregate_verify" ->
        assert_eth_fast_aggregate_verify(input, output)

      handler ->
        raise "Unknown case: #{handler}"
    end
  end

  defp assert_sign(%{message: message, privkey: private_key}, output) do
    case output do
      nil ->
        assert {result, _error_msg} = Bls.sign(private_key, message)
        assert result == :error

      output ->
        assert {:ok, signature} = Bls.sign(private_key, message)
        assert signature == output
    end
  end

  defp assert_aggregate(signatures, output) do
    case output do
      nil ->
        assert {result, _error_msg} = Bls.aggregate(signatures)
        assert result == :error

      output ->
        assert {:ok, signature} = Bls.aggregate(signatures)
        assert signature == output
    end
  end

  defp assert_eth_aggregate_pubkeys(pubkeys, output) do
    case output do
      nil ->
        assert {result, _error_msg} = Bls.eth_aggregate_pubkeys(pubkeys)
        assert result == :error

      output ->
        assert {:ok, agg_pubkey} = Bls.eth_aggregate_pubkeys(pubkeys)
        assert agg_pubkey == output
    end
  end

  defp assert_fast_aggregate_verify(
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

  defp assert_aggregate_verify(
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

  defp assert_verify(
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

  defp assert_eth_fast_aggregate_verify(
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
