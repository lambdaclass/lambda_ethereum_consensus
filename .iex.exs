head_root = fn ->
  store = LambdaEthereumConsensus.Store.StoreDb.fetch_store() |> elem(1)

  {fn -> store end,
   store |> LambdaEthereumConsensus.ForkChoice.Head.get_head() |> elem(1) |> LambdaEthereumConsensus.Utils.format_binary()}
end


block_info = fn "0x"<>root -> LambdaEthereumConsensus.Store.Blocks.get_block_info(root |> Base.decode16(case: :lower) |> elem(1)) end
