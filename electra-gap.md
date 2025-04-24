# Implementation Gaps for electra Upgrade

This document will guide you through our step-by-step plan for the implementation of the new electra fork. We’ve broken the work into three clear phases to make our goals and priorities easy to follow. This is a living document, so we will update it as we progress through the implementation.

## Roadmap

| Status | Phase                                    | What & Why                                           | Key Steps                                                                 | Testing                                            |
|:----:|:------------------------------------------|:------------------------------------------------------|:---------------------------------------------------------------------------|:---------------------------------------------------|
| 🏗️   | [Phase 1: Beacon Chain Implementation](#phase-1-beacon-chain-implementation)     | Build the electra-upgraded beacon chain core         | • Apply electra-specific changes<br>• Run & pass full spec tests           | Run spec suite (`make spec-test`), aim for 0 failures |
| ⌛   | [Phase 2: P2P & Sepolia Long-Running Sessions](#phase-2-p2p--sepolia-long-running-sessions)   | Ensure stability on Sepolia                          | • Implement the P2P changes <br> • Deploy the node on our server pointing to Sepolia<br>• Fix every issue we found that interrupts the node execution | Continuous uptime checks & up-to-date block processing for 72+ hrs in Sepolia|
| ⌛   | [Phase 3: Validator Upgrades](#phase-3-validator-upgrades) | Ensure validators duties on devnets              |• Implement the honest validator changes<br>• Make assertoor work<br> • Test via Kurtosis & Assertoor | Execute Kurtosis scenarios & Assertoor with continuous uptime checks and up-to-date validation duties for 72+ hrs on kurtosis   |

### Why this Order

We kick off with the beacon chain implementation because passing the full spec test suite is critical for protocol correctness and a solid foundation. Once all tests are green, we move to Phase 2 for prolonged Sepolia sessions and the implementation of the p2p interface changes, ensuring real-world testnet stability before mainnet moves to electra which would limit our network options before we upgrade. This will allow us to continue running long session on our servers and monitor the node execution given that just the block/epoch processing and state transitions are needed for this. With a stable node confirmed, Phase 3 begins, upgrading the validator logic, tested through Kurtosis and Assertoor to finalize the electra upgrade roadmap.

### Next Steps

Once we finish the whole electra upgrade we have a clear path to follow for the next steps:
- **Hooli long running sessions:** Right now Holesky was not an option for us because of performance issues, we need to test on Hooli and see if we can run the node on it on acceptable performance. This effort will be in parallel to the performance optimization one.
- **Performance optimization:** We need to run the node on Hooli and mainnet to identify and fix the current bottlenecks, specially on block and epoch processing.
- **Electra code enhancements:** During the implementation, some complex functions were identified that could be simplified. They are mostly related to how to manage early returns in already large python reference functions and port the logic to elixir. We will work on those to improve the code quality and make it easier to maintain in the future.

## Current Status

Right now we are at the [Beacon Chain Implementation](#phase-1-beacon-chain-implementation) phase, our current spec test results for the past weeks are:

- **April 15th, 2025:** `11370 tests, 2003 failures, 784 skipped`
- **April 22th, 2025:** `11370 tests, 165 failures, 784 skipped`

**Note:** The aim is to reach `0` failures before next week, so we can start the long running sessions on Sepolia. Also, we want to validate the 784 test skipped on the second phase.

## Implementation Gap

Here we will detail the current implementation gaps with the specs and the way to test every phase. The initial one is the larger to implement but it has the most clear way to validate it (spec-tests). The next phases are smaller but they need to be validated on long running sessions both in devnets and testnets.

### Phase 1: Beacon Chain Implementation

We are at `49/57` (86%) of the [beacon chain changes](docs/specs/electra/beacon-chain.md), and most of the remaining functions are already in progress. We have still `108/11370` spec test failures, but we are working on them. The skipped tests were there previous to the electra upgrade, so we will work on them if needed after we finish the first phase. Our aim as mentioned before is to reach `0` failures before going to the next phase.


The current status of the implementation in the [electra-support](https://github.com/lambdaclass/lambda_ethereum_consensus/tree/electra-support) branch is as follows:

#### Containers (13/13 - 100%)

- [x] New `PendingDeposit` ([Spec](docs/specs/electra/beacon-chain.md#pendingdeposit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] New `PendingPartialWithdrawal` ([Spec](docs/specs/electra/beacon-chain.md#pendingpartialwithdrawal), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] New `PendingConsolidation` ([Spec](docs/specs/electra/beacon-chain.md#pendingconsolidation), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] New `DepositRequest` ([Spec](docs/specs/electra/beacon-chain.md#depositrequest), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] New `WithdrawalRequest` ([Spec](docs/specs/electra/beacon-chain.md#withdrawalrequest), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] New `ConsolidationRequest` ([Spec](docs/specs/electra/beacon-chain.md#consolidationrequest), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] New `ExecutionRequests` ([Spec](docs/specs/electra/beacon-chain.md#executionrequests), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] New `SingleAttestation` ([Spec](docs/specs/electra/beacon-chain.md#singleattestation), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] Modified `AttesterSlashing` ([Spec](docs/specs/electra/beacon-chain.md#attesterslashing), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] Modified `BeaconBlockBody` ([Spec](docs/specs/electra/beacon-chain.md#beaconblockbody), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] Modified `Attestation` ([Spec](docs/specs/electra/beacon-chain.md#attestation), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] Modified `IndexedAttestation` ([Spec](docs/specs/electra/beacon-chain.md#indexedattestation), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))
- [x] Modified `BeaconState` ([Spec](docs/specs/electra/beacon-chain.md#beaconstate), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1400))

#### Predicates (6/6 - 100%)

- [x] Modified `is_eligible_for_activation_queue` ([Spec](docs/specs/electra/beacon-chain.md#modified-is_eligible_for_activation_queue), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] New `is_compounding_withdrawal_credential` ([Spec](docs/specs/electra/beacon-chain.md#new-is_compounding_withdrawal_credential), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] New `has_compounding_withdrawal_credential` ([Spec](docs/specs/electra/beacon-chain.md#new-has_compounding_withdrawal_credential), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] New `has_execution_withdrawal_credential` ([Spec](docs/specs/electra/beacon-chain.md#new-has_execution_withdrawal_credential), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] Modified `is_fully_withdrawable_validator` ([Spec](docs/specs/electra/beacon-chain.md#modified-is_fully_withdrawable_validator), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] Modified `is_partially_withdrawable_validator` ([Spec](docs/specs/electra/beacon-chain.md#modified-is_partially_withdrawable_validator), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))


#### Beacon State Accessors (6/6 - 100%)

- [x] Modified `get_attesting_indices` ([Spec](docs/specs/electra/beacon-chain.md#modified-get_attesting_indices), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] Modified `get_next_sync_committee_indices` ([Spec](docs/specs/electra/beacon-chain.md#modified-get_next_sync_committee_indices), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1417))
- [x] New `get_balance_churn_limit` ([Spec](docs/specs/electra/beacon-chain.md#new-get_balance_churn_limit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))
- [x] New `get_activation_exit_churn_limit` ([Spec](docs/specs/electra/beacon-chain.md#new-get_activation_exit_churn_limit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))
- [x] New `get_consolidation_churn_limit` ([Spec](docs/specs/electra/beacon-chain.md#new-get_consolidation_churn_limit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1426))
- [x] New `get_pending_balance_to_withdraw` ([Spec](docs/specs/electra/beacon-chain.md#new-get_pending_balance_to_withdraw), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1426))

#### Beacon State Mutators (6/6 - 100%)

- [x] Modified `initiate_validator_exit` ([Spec](docs/specs/electra/beacon-chain.md#modified-initiate_validator_exit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))
- [x] New `switch_to_compounding_validator` ([Spec](docs/specs/electra/beacon-chain.md#new-switch_to_compounding_validator), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1426))
- [x] New `queue_excess_active_balance` ([Spec](docs/specs/electra/beacon-chain.md#new-queue_excess_active_balance), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1426))
- [x] New `compute_exit_epoch_and_update_churn` ([Spec](docs/specs/electra/beacon-chain.md#new-compute_exit_epoch_and_update_churn), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))
- [x] New `compute_consolidation_epoch_and_update_churn` ([Spec](docs/specs/electra/beacon-chain.md#new-compute_consolidation_epoch_and_update_churn), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1426))
- [x] Modified `slash_validator` ([Spec](docs/specs/electra/beacon-chain.md#modified-slash_validator), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))

#### Miscellaneous (3/3 - 100%)

- [x] New `get_committee_indices` ([Spec](docs/specs/electra/beacon-chain.md#new-get_committee_indices), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] Modified `compute_proposer_index` ([Spec](docs/specs/electra/beacon-chain.md#modified-compute_proposer_index), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1417))
- [x] New `get_max_effective_balance` ([Spec](docs/specs/electra/beacon-chain.md#new-get_max_effective_balance), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))

#### Epoch Processing (8/8 - 100%)

- [x] Modified `process_epoch` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_epoch), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1428))
- [x] Modified `process_registry_updates` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_registry_updates), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))
- [x] Modified `process_slashings` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_slashings), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1417))
- [x] New `apply_pending_deposit` ([Spec](docs/specs/electra/beacon-chain.md#new-apply_pending_deposit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1424))
- [x] New `process_pending_deposits` ([Spec](docs/specs/electra/beacon-chain.md#new-process_pending_deposits), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1424))
- [x] New `process_pending_consolidations` ([Spec](docs/specs/electra/beacon-chain.md#new-process_pending_consolidations), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1428))
- [x] Modified `process_effective_balance_updates` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_effective_balance_updates), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1428))
- [x] Modified `get_validator_from_deposit` ([Spec](docs/specs/electra/beacon-chains.md#modified-get_validator_from_deposit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1424))

#### Block Processing (10/12 - 83%)

- [ ] Modified `process_withdrawals` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_withdrawals))
- [ ] Modified `process_execution_payload` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_execution_payload))
- [x] Modified `process_operations` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_operations), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1424))
- [x] Modified `process_attestation` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_attestation), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1426))
- [x] Modified `process_deposit` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_deposit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1424))
- [x] Modified `process_voluntary_exit` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_voluntary_exit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1426))
- [x] New `process_withdrawal_request` ([Spec](docs/specs/electra/beacon-chain.md#new-process_withdrawal_request), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1426))
- [x] New `process_deposit_request` ([Spec](docs/specs/electra/beacon-chain.md#new-process_deposit_request), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1424))
- [x] New `process_consolidation_request` ([Spec](docs/specs/electra/beacon-chain.md#new-process_consolidation_request), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1426))
- [x] New `is_valid_deposit_signature` ([Spec](docs/specs/electra/beacon-chain.md#new-is_valid_deposit_signature), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1424))
- [x] Modified `add_validator_to_registry` ([Spec](docs/specs/electra/beacon-chain.md#modified-add_validator_to_registry), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1424))
- [x] Modified `apply_deposit` ([Spec](docs/specs/electra/beacon-chain.md#modified-apply_deposit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1424))

#### Execution Engine (0/3 - 0%)

- [ ] Modified `is_valid_block_hash` ([Spec](docs/specs/electra/beacon-chain.md#modified-is_valid_block_hash))
- [ ] Modified `notify_new_payload` ([Spec](docs/specs/electra/beacon-chain.md#modified-notify_new_payload))
- [ ] Modified `verify_and_notify_new_payload` ([Spec](docs/specs/electra/beacon-chain.md#modified-verify_and_notify_new_payload))

## Phase 2: P2P & Sepolia Long-Running Sessions

We didn't start this phase yet, its goals are:

- [P2P electra changes](docs/specs/electra/p2p-interface.md) implementated.
- To have a stable node processing state transitions in testnets, especially Sepolia. 
- Validate the remaining 784 skipped tests to make sure they are not masking any issues.

The aim is to have the node running on Sepolia uninterrupted for 72+ hrs. The following is the implementation gap for this phase:

### Networking (0/8 - 0% Complete)

- [ ] Updated `beacon_block` topic validation ([Spec](docs/specs/electra/p2p-interface.md#beacon_block))
- [ ] Updated `beacon_aggregate_and_proof` topic validation ([Spec](docs/specs/electra/p2p-interface.md#beacon_aggregate_and_proof))
- [ ] Updated `blob_sidecar_{subnet_id}` topic validation ([Spec](docs/specs/electra/p2p-interface.md#blob_sidecar_subnet_id))
- [ ] Updated `beacon_attestation_{subnet_id}` topic validation ([Spec](docs/specs/electra/p2p-interface.md#beacon_attestation_subnet_id))
- [ ] Updated `BeaconBlocksByRange v2` ([Spec](docs/specs/electra/p2p-interface.md#beaconblocksbyrange-v2))
- [ ] Updated `BeaconBlocksByRoot v2` ([Spec](docs/specs/electra/p2p-interface.md#beaconblocksbyroot-v2))
- [ ] Updated `BlobSidecarsByRange v1` ([Spec](docs/specs/electra/p2p-interface.md#blobsidecarsbyrange-v1))
- [ ] Updated `BlobSidecarsByRoot v1` ([Spec](docs/specs/electra/p2p-interface.md#blobsidecarsbyroot-v1))

## Phase 3: Validator Upgrades

We didn't start this phase yet, its goals are:
- [Honest validator changes](docs/specs/electra/validator.md) implemented.
- To have a stable node processing validator duties in a kurtosis devnet.
- Have assertoor working with automatic test for the validator duties.

The aim is to have the node running on kurtosis uninterrupted for 72+ hrs. The following is the implementation gap for this phase:

### Honest Validator (0/9 - 0% Complete)

- [ ] Modified `GetPayloadResponse` ([Spec](docs/specs/electra/validator.md#modified-getpayloadresponse))
- [ ] Modified `AggregateAndProof` ([Spec](docs/specs/electra/validator.md#aggregateandproof))
- [ ] Modified `SignedAggregateAndProof` ([Spec](docs/specs/electra/validator.md#signedaggregateandproof))
- [ ] Modified `get_payload` ([Spec](docs/specs/electra/validator.md#modified-get_payload))
- [ ] Updated `prepare_execution_payload` ([Spec](docs/specs/electra/validator.md#execution-payload))
- [ ] New `get_execution_requests` ([Spec](docs/specs/electra/validator.md#execution-requests))
- [ ] Updated `compute_subnet_for_blob_sidecar` ([Spec](docs/specs/electra/validator.md#sidecar))
- [ ] Updated `construct attestation` ([Spec](docs/specs/electra/validator.md#construct-attestation))
- [ ] Updated `construct aggregate` ([Spec](docs/specs/electra/validator.md#construct-aggregate))


## Changelog
- **April 10th, 2025:** Created the document with the implementation gap.
- **April 22th, 2025:** Updated the document with a clear roadmap, next steps and detailed current status.