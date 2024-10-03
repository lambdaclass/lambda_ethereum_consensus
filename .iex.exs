head_root = fn ->
  store = LambdaEthereumConsensus.Store.StoreDb.fetch_store() |> elem(1)

  {fn -> store end,
   store |> LambdaEthereumConsensus.ForkChoice.Head.get_head() |> elem(1) |> LambdaEthereumConsensus.Utils.format_shorten_binary()}
end
