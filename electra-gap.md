# Implementation Gaps for Electra Upgrade

This document outlines the gaps in the current implementation of the Electra. It's still a WIP.

## Difference Between Updated and Modified

- **Updated**: Changes in validation rules, protocols, or external behaviors. These changes may not directly alter the logic of the implementation.
- **Modified**: Refers to direct changes made to the code or logic of an existing function, container, or process to accommodate new requirements or features.

## Containers

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

## Predicates

- [x] Modified `is_eligible_for_activation_queue` ([Spec](docs/specs/electra/beacon-chain.md#modified-is_eligible_for_activation_queue), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] New `is_compounding_withdrawal_credential` ([Spec](docs/specs/electra/beacon-chain.md#new-is_compounding_withdrawal_credential), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] New `has_compounding_withdrawal_credential` ([Spec](docs/specs/electra/beacon-chain.md#new-has_compounding_withdrawal_credential), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] New `has_execution_withdrawal_credential` ([Spec](docs/specs/electra/beacon-chain.md#new-has_execution_withdrawal_credential), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] Modified `is_fully_withdrawable_validator` ([Spec](docs/specs/electra/beacon-chain.md#modified-is_fully_withdrawable_validator), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] Modified `is_partially_withdrawable_validator` ([Spec](docs/specs/electra/beacon-chain.md#modified-is_partially_withdrawable_validator), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))


## Beacon State Accessors

- [x] Modified `get_attesting_indices` ([Spec](docs/specs/electra/beacon-chain.md#modified-get_attesting_indices), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] Modified `get_next_sync_committee_indices` ([Spec](docs/specs/electra/beacon-chain.md#modified-get_next_sync_committee_indices), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1417))
- [x] New `get_balance_churn_limit` ([Spec](docs/specs/electra/beacon-chain.md#new-get_balance_churn_limit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))
- [x] New `get_activation_exit_churn_limit` ([Spec](docs/specs/electra/beacon-chain.md#new-get_activation_exit_churn_limit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))
- [ ] New `get_consolidation_churn_limit` ([Spec](docs/specs/electra/beacon-chain.md#new-get_consolidation_churn_limit))
- [ ] New `get_pending_balance_to_withdraw` ([Spec](docs/specs/electra/beacon-chain.md#new-get_pending_balance_to_withdraw))

## Beacon State Mutators

- [x] Modified `initiate_validator_exit` ([Spec](docs/specs/electra/beacon-chain.md#modified-initiate_validator_exit), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))
- [ ] New `switch_to_compounding_validator` ([Spec](docs/specs/electra/beacon-chain.md#new-switch_to_compounding_validator))
- [ ] New `queue_excess_active_balance` ([Spec](docs/specs/electra/beacon-chain.md#new-queue_excess_active_balance))
- [x] New `compute_exit_epoch_and_update_churn` ([Spec](docs/specs/electra/beacon-chain.md#new-compute_exit_epoch_and_update_churn), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))
- [ ] New `compute_consolidation_epoch_and_update_churn` ([Spec](docs/specs/electra/beacon-chain.md#new-compute_consolidation_epoch_and_update_churn))
- [x] Modified `slash_validator` ([Spec](docs/specs/electra/beacon-chain.md#modified-slash_validator), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))

## Miscellaneous

- [x] New `get_committee_indices` ([Spec](docs/specs/electra/beacon-chain.md#new-get_committee_indices), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))
- [x] Modified `compute_proposer_index` ([Spec](docs/specs/electra/beacon-chain.md#modified-compute_proposer_index), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1417))
- [x] New `get_max_effective_balance` ([Spec](docs/specs/electra/beacon-chain.md#new-get_max_effective_balance), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1419))

## Epoch Processing

- [ ] Modified `process_epoch` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_epoch))
- [x] Modified `process_registry_updates` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_registry_updates), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1420))
- [x] Modified `process_slashings` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_slashings), [PR](https://github.com/lambdaclass/lambda_ethereum_consensus/pull/1417))
- [ ] New `apply_pending_deposit` ([Spec](docs/specs/electra/beacon-chain.md#new-apply_pending_deposit))
- [ ] New `process_pending_deposits` ([Spec](docs/specs/electra/beacon-chain.md#new-process_pending_deposits))
- [ ] New `process_pending_consolidations` ([Spec](docs/specs/electra/beacon-chain.md#new-process_pending_consolidations))
- [ ] Modified `process_effective_balance_updates` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_effective_balance_updates))

## Block Processing

- [ ] Modified `process_withdrawals` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_withdrawals))
- [ ] Modified `process_execution_payload` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_execution_payload))
- [ ] Modified `process_operations` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_operations))
- [ ] Modified `process_attestation` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_attestation))
- [ ] Modified `process_deposit` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_deposit))
- [ ] Modified `process_voluntary_exit` ([Spec](docs/specs/electra/beacon-chain.md#modified-process_voluntary_exit))
- [ ] New `process_withdrawal_request` ([Spec](docs/specs/electra/beacon-chain.md#new-process_withdrawal_request))
- [ ] New `process_deposit_request` ([Spec](docs/specs/electra/beacon-chain.md#new-process_deposit_request))
- [ ] New `process_consolidation_request` ([Spec](docs/specs/electra/beacon-chain.md#new-process_consolidation_request))

## Execution Engine

- [ ] Modified `is_valid_block_hash` ([Spec](docs/specs/electra/beacon-chain.md#modified-is_valid_block_hash))
- [ ] Modified `notify_new_payload` ([Spec](docs/specs/electra/beacon-chain.md#modified-notify_new_payload))
- [ ] Modified `verify_and_notify_new_payload` ([Spec](docs/specs/electra/beacon-chain.md#modified-verify_and_notify_new_payload))

## Networking

- [ ] Updated `beacon_block` topic validation ([Spec](docs/specs/electra/p2p-interface.md#beacon_block))
- [ ] Updated `beacon_aggregate_and_proof` topic validation ([Spec](docs/specs/electra/p2p-interface.md#beacon_aggregate_and_proof))
- [ ] Updated `blob_sidecar_{subnet_id}` topic validation ([Spec](docs/specs/electra/p2p-interface.md#blob_sidecar_subnet_id))
- [ ] Updated `beacon_attestation_{subnet_id}` topic validation ([Spec](docs/specs/electra/p2p-interface.md#beacon_attestation_subnet_id))
- [ ] Updated `BeaconBlocksByRange v2` ([Spec](docs/specs/electra/p2p-interface.md#beaconblocksbyrange-v2))
- [ ] Updated `BeaconBlocksByRoot v2` ([Spec](docs/specs/electra/p2p-interface.md#beaconblocksbyroot-v2))
- [ ] Updated `BlobSidecarsByRange v1` ([Spec](docs/specs/electra/p2p-interface.md#blobsidecarsbyrange-v1))
- [ ] Updated `BlobSidecarsByRoot v1` ([Spec](docs/specs/electra/p2p-interface.md#blobsidecarsbyroot-v1))

## Honest Validator

- [ ] Modified `GetPayloadResponse` ([Spec](docs/specs/electra/validator.md#modified-getpayloadresponse))
- [ ] Modified `AggregateAndProof` ([Spec](docs/specs/electra/validator.md#aggregateandproof))
- [ ] Modified `SignedAggregateAndProof` ([Spec](docs/specs/electra/validator.md#signedaggregateandproof))
- [ ] Modified `get_payload` ([Spec](docs/specs/electra/validator.md#modified-get_payload))
- [ ] Updated `prepare_execution_payload` ([Spec](docs/specs/electra/validator.md#execution-payload))
- [ ] New `get_execution_requests` ([Spec](docs/specs/electra/validator.md#execution-requests))
- [ ] Updated `compute_subnet_for_blob_sidecar` ([Spec](docs/specs/electra/validator.md#sidecar))
- [ ] Updated `construct attestation` ([Spec](docs/specs/electra/validator.md#construct-attestation))
- [ ] Updated `construct aggregate` ([Spec](docs/specs/electra/validator.md#construct-aggregate))

## Fork Logic

- [ ] Modified `compute_fork_version` ([Spec](docs/specs/electra/fork.md#modified-compute_fork_version))
- [ ] New `upgrade_to_electra` ([Spec](docs/specs/electra/fork.md#upgrade_to_electra))
