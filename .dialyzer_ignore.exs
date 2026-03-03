# Dialyzer warnings to ignore.
#
# Most of these are caused by HardForkAliasInjection.fulu?() being a
# compile-time constant (true when .fork_version is "fulu"). This makes
# the non-fulu branches dead code, which dialyzer correctly identifies
# but is intentional by design. These will naturally resolve when the
# fork gate is removed post-Fulu activation.
[
  # --- Fork-gate dead code: "Guard test true =:= nil can never succeed" ---
  # All from `if HardForkAliasInjection.fulu?()` being always true.
  {"lib/lambda_ethereum_consensus/beacon/pending_blocks.ex", :guard_fail},
  {"lib/lambda_ethereum_consensus/fork_choice/handlers.ex", :guard_fail},
  {"lib/lambda_ethereum_consensus/state_transition/operations.ex", :guard_fail},
  {"lib/lambda_ethereum_consensus/state_transition/state_transition.ex", :guard_fail},
  {"lib/lambda_ethereum_consensus/validator/block_builder.ex", :guard_fail},
  {"lib/lambda_ethereum_consensus/validator/validator.ex", :guard_fail},
  {"lib/libp2p_port.ex", :guard_fail},
  {"lib/types/beacon_chain/beacon_state.ex", :guard_fail},
  {"lib/types/p2p/metadata.ex", :guard_fail},
  {"test/spec/runners/fork_choice.ex", :guard_fail},

  # --- Fork-gate dead code: unused functions from non-fulu branches ---
  {"lib/lambda_ethereum_consensus/beacon/pending_blocks.ex", :unused_fun},
  {"lib/lambda_ethereum_consensus/fork_choice/handlers.ex", :unused_fun},
  {"lib/lambda_ethereum_consensus/validator/block_builder.ex", :unused_fun},
  {"lib/lambda_ethereum_consensus/validator/validator.ex", :unused_fun},
]
