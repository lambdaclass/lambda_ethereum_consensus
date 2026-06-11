alias LambdaEthereumConsensus.ForkChoice
alias LambdaEthereumConsensus.ForkChoice.Head
alias LambdaEthereumConsensus.StateTransition.Misc
alias LambdaEthereumConsensus.Store.Blocks
alias LambdaEthereumConsensus.Store.StoreDb
alias LambdaEthereumConsensus.Utils

# Some convenience functions for debugging
store = fn -> StoreDb.fetch_store() |> elem(1) end

head_root = fn -> store.() |> Head.get_head() |> elem(1) |> Utils.format_binary() end
head_slot = fn -> store.() |> Head.get_head() |> elem(1) |> Blocks.get_block_info() |> then(& &1.signed_block.message.slot) end

store_calculated_slot = fn -> store.() |> ForkChoice.get_current_slot() end

epoch = fn slot -> slot |> Misc.compute_epoch_at_slot() end

block_info = fn "0x"<>root -> root |> Base.decode16(case: :lower) |> elem(1) |> Blocks.get_block_info() end

blocks_by_status = fn status -> Blocks.get_blocks_with_status(status) |> elem(1) end
blocks_by_status_count = fn status -> blocks_by_status.(status) |> Enum.count() end

# Memory introspection (see lib/utils/mem.ex)
alias LambdaEthereumConsensus.Mem
# Quick access:
#   Mem.report()              — full memory report
#   Mem.ets_tables()          — all ETS tables ranked by memory
#   Mem.top_processes(10)     — top 10 processes by heap
#   Mem.state_cache_detail()  — per-entry BlockStates breakdown
#   Mem.checkpoint_detail()   — checkpoint states table
#   Mem.binary_stats()        — binary/refc binary pressure
#   Mem.cache_tables()        — StateTransition cache sizes
#   snap = Mem.snapshot(); ...; Mem.diff_snapshot(snap) — delta tracking
