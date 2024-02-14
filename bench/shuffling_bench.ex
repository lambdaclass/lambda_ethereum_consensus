alias LambdaEthereumConsensus.StateTransition.Shuffling
alias LambdaEthereumConsensus.StateTransition.Misc

index_count = 1000
seed = :crypto.strong_rand_bytes(32)
input = 0..(index_count - 1)//1

Benchee.run(
  %{
    "shuffle_list" => fn ->
      Shuffling.shuffle_list(Aja.Vector.new(input), seed)
    end,
    "compute_shuffled_index" => fn ->
      for index <- input do
        Misc.compute_shuffled_index(index, index_count, seed)
      end
    end
  },
  warmup: 2,
  time: 5
)
