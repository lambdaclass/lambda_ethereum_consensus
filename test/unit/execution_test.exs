defmodule Unit.ExecutionTest do
  alias LambdaEthereumConsensus.Execution.EngineApi
  alias LambdaEthereumConsensus.Execution.ExecutionClient
  use ExUnit.Case

  use Patch

  # Sepolia genesis block, as given by a geth client
  @example_block_header %{
    "base_fee_per_gas" => "0x3b9aca00",
    "difficulty" => "0x20000",
    "extra_data" => "0x5365706f6c69612c20417468656e732c204174746963612c2047726565636521",
    "gas_limit" => "0x1c9c380",
    "gas_used" => "0x0",
    "hash" => "0x25a5cc106eea7138acab33231d7160d69cb777ee0c2c553fcddf5138993e6dd9",
    "logs_bloom" =>
      "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "miner" => "0x0000000000000000000000000000000000000000",
    "mix_hash" => "0x0000000000000000000000000000000000000000000000000000000000000000",
    "nonce" => "0x0000000000000000",
    "number" => "0x0",
    "parent_hash" => "0x0000000000000000000000000000000000000000000000000000000000000000",
    "receipts_root" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
    "sha3_uncles" => "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
    "size" => "0x225",
    "state_root" => "0x5eb6e371a698b8d68f665192350ffcecbbbf322916f4b51bd79bb6887da3f494",
    "timestamp" => "0x6159af19",
    "total_difficulty" => "0x20000",
    "transactions" => [],
    "transactions_root" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
    "uncles" => []
  }

  test "decode block from json is OK" do
    patch(EngineApi, :get_block_header, fn nil -> {:ok, @example_block_header} end)
    assert {:ok, block_info} = ExecutionClient.get_block_metadata(nil)

    expected_hash =
      "25a5cc106eea7138acab33231d7160d69cb777ee0c2c553fcddf5138993e6dd9"
      |> Base.decode16!(case: :mixed)

    assert block_info.block_hash == expected_hash
    assert block_info.block_number == 0
    assert block_info.timestamp == 1_633_267_481
  end
end
