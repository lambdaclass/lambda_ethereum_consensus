alias LambdaEthereumConsensus.Execution.ExecutionChain

# The --mode db flag is needed to run this benchmark.

compressed_tree = File.read!("deposit_tree_file")
{:ok, encoded_tree} = :snappyer.decompress(compressed_tree)
deposit_tree = :erlang.binary_to_term(encoded_tree)

Benchee.run(
  %{
    "ExecutionChain.put" => fn v -> ExecutionChain.put("", v) end
  },
  warmup: 2,
  time: 5,
  inputs: %{
    "DepositTree" => deposit_tree
  }
)

Benchee.run(
  %{
    "ExecutionChain.get" => fn -> ExecutionChain.get("") end
  },
  warmup: 2,
  time: 5
)
