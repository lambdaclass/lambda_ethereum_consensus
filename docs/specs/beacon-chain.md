# Fulu -- The Beacon Chain

## Table of contents

- [Introduction](#introduction)
- [Notation](#notation)
- [Custom types](#custom-types)
- [Constants](#constants)
  - [Misc](#misc)
  - [Withdrawal prefixes](#withdrawal-prefixes)
  - [Execution layer triggered requests](#execution-layer-triggered-requests)
  - [Domain types](#domain-types)
  - [Participation flag indices](#participation-flag-indices)
  - [Incentivization weights](#incentivization-weights)
  - [Blob](#blob)
- [Preset](#preset)
  - [Misc](#misc-1)
  - [Gwei values](#gwei-values)
  - [Time parameters](#time-parameters)
  - [State list lengths](#state-list-lengths)
  - [Rewards and penalties](#rewards-and-penalties)
  - [Max operations per block](#max-operations-per-block)
  - [Sync committee](#sync-committee)
  - [Execution](#execution)
  - [Withdrawals processing](#withdrawals-processing)
  - [Pending deposits processing](#pending-deposits-processing)
- [Configuration](#configuration)
  - [Genesis settings](#genesis-settings)
  - [Time parameters](#time-parameters-1)
  - [Validator cycle](#validator-cycle)
  - [Inactivity penalties](#inactivity-penalties)
  - [Transition settings](#transition-settings)
  - [Execution](#execution-1)
  - [Blob schedule](#blob-schedule)
- [Containers](#containers)
  - [Misc dependencies](#misc-dependencies)
    - [`Fork`](#fork)
    - [`ForkData`](#forkdata)
    - [`Checkpoint`](#checkpoint)
    - [`Validator`](#validator)
    - [`AttestationData`](#attestationdata)
    - [`IndexedAttestation`](#indexedattestation)
    - [`PendingAttestation`](#pendingattestation)
    - [`Eth1Data`](#eth1data)
    - [`HistoricalBatch`](#historicalbatch)
    - [`DepositMessage`](#depositmessage)
    - [`DepositData`](#depositdata)
    - [`BeaconBlockHeader`](#beaconblockheader)
    - [`SigningData`](#signingdata)
    - [`ExecutionPayload`](#executionpayload)
    - [`ExecutionPayloadHeader`](#executionpayloadheader)
    - [`Withdrawal`](#withdrawal)
    - [`BLSToExecutionChange`](#blstoexecutionchange)
    - [`SignedBLSToExecutionChange`](#signedblstoexecutionchange)
    - [`HistoricalSummary`](#historicalsummary)
    - [`PendingDeposit`](#pendingdeposit)
    - [`PendingPartialWithdrawal`](#pendingpartialwithdrawal)
    - [`PendingConsolidation`](#pendingconsolidation)
    - [`DepositRequest`](#depositrequest)
    - [`WithdrawalRequest`](#withdrawalrequest)
    - [`ConsolidationRequest`](#consolidationrequest)
    - [`ExecutionRequests`](#executionrequests)
    - [`BlobParameters`](#blobparameters)
  - [Beacon operations](#beacon-operations)
    - [`ProposerSlashing`](#proposerslashing)
    - [`AttesterSlashing`](#attesterslashing)
    - [`Attestation`](#attestation)
    - [`SingleAttestation`](#singleattestation)
    - [`Deposit`](#deposit)
    - [`VoluntaryExit`](#voluntaryexit)
  - [Beacon blocks](#beacon-blocks)
    - [`BeaconBlockBody`](#beaconblockbody)
    - [`BeaconBlock`](#beaconblock)
  - [Beacon state](#beacon-state)
    - [`BeaconState`](#beaconstate)
  - [Signed envelopes](#signed-envelopes)
    - [`SignedVoluntaryExit`](#signedvoluntaryexit)
    - [`SignedBeaconBlock`](#signedbeaconblock)
    - [`SignedBeaconBlockHeader`](#signedbeaconblockheader)
    - [`SyncAggregate`](#syncaggregate)
    - [`SyncCommittee`](#synccommittee)
- [Helper functions](#helper-functions)
  - [Math](#math)
    - [`integer_squareroot`](#integer_squareroot)
    - [`xor`](#xor)
    - [`uint_to_bytes`](#uint_to_bytes)
    - [`bytes_to_uint64`](#bytes_to_uint64)
    - [`saturating_sub`](#saturating_sub)
  - [Crypto](#crypto)
    - [`hash`](#hash)
    - [`hash_tree_root`](#hash_tree_root)
    - [BLS signatures](#bls-signatures)
  - [Predicates](#predicates)
    - [`is_active_validator`](#is_active_validator)
    - [`is_eligible_for_activation_queue`](#is_eligible_for_activation_queue)
    - [`is_eligible_for_activation`](#is_eligible_for_activation)
    - [`is_slashable_validator`](#is_slashable_validator)
    - [`is_slashable_attestation_data`](#is_slashable_attestation_data)
    - [`is_valid_indexed_attestation`](#is_valid_indexed_attestation)
    - [`is_valid_merkle_branch`](#is_valid_merkle_branch)
    - [`is_merge_transition_complete`](#is_merge_transition_complete)
    - [`is_merge_transition_block`](#is_merge_transition_block)
    - [`is_execution_enabled`](#is_execution_enabled)
    - [`has_eth1_withdrawal_credential`](#has_eth1_withdrawal_credential)
    - [`is_compounding_withdrawal_credential`](#is_compounding_withdrawal_credential)
    - [`has_compounding_withdrawal_credential`](#has_compounding_withdrawal_credential)
    - [`has_execution_withdrawal_credential`](#has_execution_withdrawal_credential)
    - [`is_fully_withdrawable_validator`](#is_fully_withdrawable_validator)
    - [`is_partially_withdrawable_validator`](#is_partially_withdrawable_validator)
  - [Misc](#misc-2)
    - [`kzg_commitment_to_versioned_hash`](#kzg_commitment_to_versioned_hash)
    - [`compute_shuffled_index`](#compute_shuffled_index)
    - [`compute_proposer_index`](#compute_proposer_index)
    - [`compute_committee`](#compute_committee)
    - [`compute_epoch_at_slot`](#compute_epoch_at_slot)
    - [`compute_start_slot_at_epoch`](#compute_start_slot_at_epoch)
    - [`compute_activation_exit_epoch`](#compute_activation_exit_epoch)
    - [`compute_fork_data_root`](#compute_fork_data_root)
    - [`compute_fork_digest`](#compute_fork_digest)
    - [`compute_domain`](#compute_domain)
    - [`compute_signing_root`](#compute_signing_root)
    - [`compute_timestamp_at_slot`](#compute_timestamp_at_slot)
    - [`add_flag`](#add_flag)
    - [`has_flag`](#has_flag)
    - [`get_index_for_new_validator`](#get_index_for_new_validator)
    - [`set_or_append_list`](#set_or_append_list)
    - [`get_committee_indices`](#get_committee_indices)
    - [`get_max_effective_balance`](#get_max_effective_balance)
    - [`get_blob_parameters`](#get_blob_parameters)
    - [`compute_proposer_indices`](#compute_proposer_indices)
  - [Beacon state accessors](#beacon-state-accessors)
    - [`get_current_epoch`](#get_current_epoch)
    - [`get_previous_epoch`](#get_previous_epoch)
    - [`get_block_root`](#get_block_root)
    - [`get_block_root_at_slot`](#get_block_root_at_slot)
    - [`get_randao_mix`](#get_randao_mix)
    - [`get_active_validator_indices`](#get_active_validator_indices)
    - [`get_validator_churn_limit`](#get_validator_churn_limit)
    - [`get_seed`](#get_seed)
    - [`get_committee_count_per_slot`](#get_committee_count_per_slot)
    - [`get_beacon_committee`](#get_beacon_committee)
    - [`get_beacon_proposer_index`](#get_beacon_proposer_index)
    - [`get_beacon_proposer_indices`](#get_beacon_proposer_indices)
    - [`get_total_balance`](#get_total_balance)
    - [`get_total_active_balance`](#get_total_active_balance)
    - [`get_domain`](#get_domain)
    - [`get_indexed_attestation`](#get_indexed_attestation)
    - [`get_attesting_indices`](#get_attesting_indices)
    - [`get_next_sync_committee_indices`](#get_next_sync_committee_indices)
    - [`get_next_sync_committee`](#get_next_sync_committee)
    - [`get_base_reward_per_increment`](#get_base_reward_per_increment)
    - [`get_base_reward`](#get_base_reward)
    - [`get_unslashed_participating_indices`](#get_unslashed_participating_indices)
    - [`get_attestation_participation_flag_indices`](#get_attestation_participation_flag_indices)
    - [`get_flag_index_deltas`](#get_flag_index_deltas)
    - [`get_inactivity_penalty_deltas`](#get_inactivity_penalty_deltas)
    - [`get_validator_activation_churn_limit`](#get_validator_activation_churn_limit)
    - [`get_balance_churn_limit`](#get_balance_churn_limit)
    - [`get_activation_exit_churn_limit`](#get_activation_exit_churn_limit)
    - [`get_consolidation_churn_limit`](#get_consolidation_churn_limit)
    - [`get_pending_balance_to_withdraw`](#get_pending_balance_to_withdraw)
  - [Beacon state mutators](#beacon-state-mutators)
    - [`increase_balance`](#increase_balance)
    - [`decrease_balance`](#decrease_balance)
    - [`initiate_validator_exit`](#initiate_validator_exit)
    - [`slash_validator`](#slash_validator)
    - [`switch_to_compounding_validator`](#switch_to_compounding_validator)
    - [`queue_excess_active_balance`](#queue_excess_active_balance)
    - [`compute_exit_epoch_and_update_churn`](#compute_exit_epoch_and_update_churn)
    - [`compute_consolidation_epoch_and_update_churn`](#compute_consolidation_epoch_and_update_churn)
- [Genesis](#genesis)
  - [Genesis state](#genesis-state)
  - [Genesis block](#genesis-block)
- [Beacon chain state transition function](#beacon-chain-state-transition-function)
  - [Epoch processing](#epoch-processing)
    - [Helper functions](#helper-functions-1)
    - [Justification and finalization](#justification-and-finalization)
    - [Inactivity scores](#inactivity-scores)
    - [Rewards and penalties](#rewards-and-penalties-1)
    - [Registry updates](#registry-updates)
    - [Slashings](#slashings)
    - [Eth1 data votes updates](#eth1-data-votes-updates)
    - [Pending deposits processing](#pending-deposits-processing-1)
    - [Pending consolidations processing](#pending-consolidations-processing)
    - [Effective balances updates](#effective-balances-updates)
    - [Slashings balances updates](#slashings-balances-updates)
    - [Randao mixes updates](#randao-mixes-updates)
    - [Historical summaries updates](#historical-summaries-updates)
    - [Participation flags updates](#participation-flags-updates)
    - [Sync committee updates](#sync-committee-updates)
    - [Proposer lookahead](#proposer-lookahead)
  - [Block processing](#block-processing)
    - [Block header](#block-header)
    - [RANDAO](#randao)
    - [Eth1 data](#eth1-data)
    - [Operations](#operations)
      - [Proposer slashings](#proposer-slashings)
      - [Attester slashings](#attester-slashings)
      - [Attestations](#attestations)
      - [Deposits](#deposits)
      - [Voluntary exits](#voluntary-exits)
      - [BLS to Execution](#bls-to-execution)
      - [Execution layer withdrawal requests](#execution-layer-withdrawal-requests)
      - [Deposit requests](#deposit-requests)
      - [Execution layer consolidation requests](#execution-layer-consolidation-requests)
    - [Sync aggregate processing](#sync-aggregate-processing)
    - [Execution payload](#execution-payload)
  - [Execution engine](#execution-engine)
    - [Request data](#request-data)
    - [Engine APIs](#engine-apis)

## Introduction

This document is the consolidated Fulu specification for the Ethereum beacon chain.

At the core of Ethereum proof-of-stake is a system chain called the "beacon chain". The beacon chain stores and manages the registry of validators. In the initial deployment phases of proof-of-stake, the only mechanism to become a validator is to make a one-way ETH transaction to a deposit contract on the Ethereum execution chain. Activation as a validator happens when deposit receipts are processed by the beacon chain, the activation balance is reached, and a queuing process is completed. Exit is either voluntary or done forcibly as a penalty for misbehavior.

This specification incorporates all changes from the following EIPs across multiple forks:

- **Altair**: Sync committees, participation flags, updated incentive accounting
- **Bellatrix**: The Merge, execution payload
- **Capella**: Withdrawals, BLS-to-execution credential changes, historical summaries
- **Deneb (EIP4844)**: Blob transactions, KZG commitments; **(EIP7045)** Extended attestation inclusion; **(EIP7514)** Activation churn limit; **(EIP7044)** Perpetual voluntary exits; **(EIP4788)** Beacon block root in EVM
- **Electra (EIP6110)**: On-chain deposit supply; **(EIP7002)** Execution layer triggerable exits; **(EIP7251)** Increase MAX_EFFECTIVE_BALANCE; **(EIP7549)** Move committee index outside Attestation; **(EIP7691)** Blob throughput increase
- **Fulu (EIP7892)**: Blob schedule (dynamic max blobs per block); **(EIP7917)** Proposer lookahead

## Notation

Code snippets appearing in `this style` are to be interpreted as Python 3 code.

## Custom types

We define the following Python custom types for type hinting and readability:

| Name | SSZ equivalent | Description |
| - | - | - |
| `Slot` | `uint64` | a slot number |
| `Epoch` | `uint64` | an epoch number |
| `CommitteeIndex` | `uint64` | a committee index at a slot |
| `ValidatorIndex` | `uint64` | a validator registry index |
| `Gwei` | `uint64` | an amount in Gwei |
| `Root` | `Bytes32` | a Merkle root |
| `Hash32` | `Bytes32` | a 256-bit hash |
| `Version` | `Bytes4` | a fork version number |
| `DomainType` | `Bytes4` | a domain type |
| `ForkDigest` | `Bytes4` | a digest of the current fork data |
| `Domain` | `Bytes32` | a signature domain |
| `BLSPubkey` | `Bytes48` | a BLS12-381 public key |
| `BLSSignature` | `Bytes96` | a BLS12-381 signature |
| `ParticipationFlags` | `uint8` | a succinct representation of 8 boolean participation flags |
| `Transaction` | `ByteList[MAX_BYTES_PER_TRANSACTION]` | either a [typed transaction envelope](https://eips.ethereum.org/EIPS/eip-2718#opaque-byte-array-rather-than-an-rlp-array) or a legacy transaction |
| `ExecutionAddress` | `Bytes20` | Address of account on the execution layer |
| `WithdrawalIndex` | `uint64` | an index of a `Withdrawal` |
| `VersionedHash` | `Bytes32` | *[New in Deneb:EIP4844]* |
| `BlobIndex` | `uint64` | *[New in Deneb:EIP4844]* |

*Note*: The `Transaction` type is a stub which is not final.

## Constants

The following values are (non-configurable) constants used throughout the specification.

### Misc

| Name | Value |
| - | - |
| `UINT64_MAX` | `uint64(2**64 - 1)` |
| `GENESIS_SLOT` | `Slot(0)` |
| `GENESIS_EPOCH` | `Epoch(0)` |
| `FAR_FUTURE_EPOCH` | `Epoch(2**64 - 1)` |
| `BASE_REWARDS_PER_EPOCH` | `uint64(4)` |
| `DEPOSIT_CONTRACT_TREE_DEPTH` | `uint64(2**5)` (= 32) |
| `JUSTIFICATION_BITS_LENGTH` | `uint64(4)` |
| `ENDIANNESS` | `'little'` |
| `PARTICIPATION_FLAG_WEIGHTS` | `[TIMELY_SOURCE_WEIGHT, TIMELY_TARGET_WEIGHT, TIMELY_HEAD_WEIGHT]` |
| `UNSET_DEPOSIT_REQUESTS_START_INDEX` | `uint64(2**64 - 1)` | *[New in Electra:EIP6110]* Value which indicates no start index has been assigned |
| `FULL_EXIT_REQUEST_AMOUNT` | `uint64(0)` | *[New in Electra:EIP7002]* Withdrawal amount used to signal a full validator exit |

### Withdrawal prefixes

| Name | Value |
| - | - |
| `BLS_WITHDRAWAL_PREFIX` | `Bytes1('0x00')` |
| `ETH1_ADDRESS_WITHDRAWAL_PREFIX` | `Bytes1('0x01')` |
| `COMPOUNDING_WITHDRAWAL_PREFIX` | `Bytes1('0x02')` | *[New in Electra:EIP7251]* Withdrawal credential prefix for a compounding validator |

### Execution layer triggered requests

| Name | Value |
| - | - |
| `DEPOSIT_REQUEST_TYPE` | `Bytes1('0x00')` |
| `WITHDRAWAL_REQUEST_TYPE` | `Bytes1('0x01')` |
| `CONSOLIDATION_REQUEST_TYPE` | `Bytes1('0x02')` |

### Domain types

| Name | Value |
| - | - |
| `DOMAIN_BEACON_PROPOSER`                | `DomainType('0x00000000')` |
| `DOMAIN_BEACON_ATTESTER`                | `DomainType('0x01000000')` |
| `DOMAIN_RANDAO`                         | `DomainType('0x02000000')` |
| `DOMAIN_DEPOSIT`                        | `DomainType('0x03000000')` |
| `DOMAIN_VOLUNTARY_EXIT`                 | `DomainType('0x04000000')` |
| `DOMAIN_SELECTION_PROOF`                | `DomainType('0x05000000')` |
| `DOMAIN_AGGREGATE_AND_PROOF`            | `DomainType('0x06000000')` |
| `DOMAIN_APPLICATION_MASK`               | `DomainType('0x00000001')` |
| `DOMAIN_SYNC_COMMITTEE`                 | `DomainType('0x07000000')` |
| `DOMAIN_SYNC_COMMITTEE_SELECTION_PROOF` | `DomainType('0x08000000')` |
| `DOMAIN_CONTRIBUTION_AND_PROOF`         | `DomainType('0x09000000')` |
| `DOMAIN_BLS_TO_EXECUTION_CHANGE`        | `DomainType('0x0A000000')` |

*Note*: `DOMAIN_APPLICATION_MASK` reserves the rest of the bitspace in `DomainType` for application usage.

### Participation flag indices

| Name | Value |
| - | - |
| `TIMELY_SOURCE_FLAG_INDEX` | `0` |
| `TIMELY_TARGET_FLAG_INDEX` | `1` |
| `TIMELY_HEAD_FLAG_INDEX` | `2` |

### Incentivization weights

| Name | Value |
| - | - |
| `TIMELY_SOURCE_WEIGHT` | `uint64(14)` |
| `TIMELY_TARGET_WEIGHT` | `uint64(26)` |
| `TIMELY_HEAD_WEIGHT` | `uint64(14)` |
| `SYNC_REWARD_WEIGHT` | `uint64(2)` |
| `PROPOSER_WEIGHT` | `uint64(8)` |
| `WEIGHT_DENOMINATOR` | `uint64(64)` |

*Note*: The sum of the weights equal `WEIGHT_DENOMINATOR`.

### Blob

| Name | Value |
| - | - |
| `VERSIONED_HASH_VERSION_KZG` | `Bytes1('0x01')` |

## Preset

*Note*: The below configuration is bundled as a preset: a bundle of configuration variables which are expected to differ between different modes of operation, e.g. testing, but not generally between different networks.

### Misc

| Name | Value |
| - | - |
| `MAX_COMMITTEES_PER_SLOT` | `uint64(2**6)` (= 64) |
| `TARGET_COMMITTEE_SIZE` | `uint64(2**7)` (= 128) |
| `MAX_VALIDATORS_PER_COMMITTEE` | `uint64(2**11)` (= 2,048) |
| `SHUFFLE_ROUND_COUNT` | `uint64(90)` |
| `HYSTERESIS_QUOTIENT` | `uint64(4)` |
| `HYSTERESIS_DOWNWARD_MULTIPLIER` | `uint64(1)` |
| `HYSTERESIS_UPWARD_MULTIPLIER` | `uint64(5)` |

### Gwei values

| Name | Value |
| - | - |
| `MIN_DEPOSIT_AMOUNT` | `Gwei(2**0 * 10**9)` (= 1,000,000,000) |
| `MAX_EFFECTIVE_BALANCE` | `Gwei(2**5 * 10**9)` (= 32,000,000,000) |
| `EFFECTIVE_BALANCE_INCREMENT` | `Gwei(2**0 * 10**9)` (= 1,000,000,000) |
| `MIN_ACTIVATION_BALANCE` | `Gwei(2**5 * 10**9)` (= 32,000,000,000) | *[New in Electra:EIP7251]* Minimum balance for a validator to become active |
| `MAX_EFFECTIVE_BALANCE_ELECTRA` | `Gwei(2**11 * 10**9)` (= 2048,000,000,000) | *[New in Electra:EIP7251]* Maximum effective balance for a compounding validator |

### Time parameters

| Name | Value | Unit | Duration |
| - | - | :-: | :-: |
| `MIN_ATTESTATION_INCLUSION_DELAY` | `uint64(2**0)` (= 1) | slots | 12 seconds |
| `SLOTS_PER_EPOCH` | `uint64(2**5)` (= 32) | slots | 6.4 minutes |
| `MIN_SEED_LOOKAHEAD` | `uint64(2**0)` (= 1) | epochs | 6.4 minutes |
| `MAX_SEED_LOOKAHEAD` | `uint64(2**2)` (= 4) | epochs | 25.6 minutes |
| `MIN_EPOCHS_TO_INACTIVITY_PENALTY` | `uint64(2**2)` (= 4) | epochs | 25.6 minutes |
| `EPOCHS_PER_ETH1_VOTING_PERIOD` | `uint64(2**6)` (= 64) | epochs | ~6.8 hours |
| `SLOTS_PER_HISTORICAL_ROOT` | `uint64(2**13)` (= 8,192) | slots | ~27 hours |

### State list lengths

| Name | Value | Unit | Duration |
| - | - | :-: | :-: |
| `EPOCHS_PER_HISTORICAL_VECTOR` | `uint64(2**16)` (= 65,536) | epochs | ~0.8 years |
| `EPOCHS_PER_SLASHINGS_VECTOR` | `uint64(2**13)` (= 8,192) | epochs | ~36 days |
| `HISTORICAL_ROOTS_LIMIT` | `uint64(2**24)` (= 16,777,216) | historical roots | ~52,262 years |
| `VALIDATOR_REGISTRY_LIMIT` | `uint64(2**40)` (= 1,099,511,627,776) | validators | |
| `PENDING_DEPOSITS_LIMIT` | `uint64(2**27)` (= 134,217,728) | pending deposits | *[New in Electra:EIP7251]* |
| `PENDING_PARTIAL_WITHDRAWALS_LIMIT` | `uint64(2**27)` (= 134,217,728) | pending partial withdrawals | *[New in Electra:EIP7251]* |
| `PENDING_CONSOLIDATIONS_LIMIT` | `uint64(2**18)` (= 262,144) | pending consolidations | *[New in Electra:EIP7251]* |

### Rewards and penalties

| Name | Value |
| - | - |
| `BASE_REWARD_FACTOR` | `uint64(2**6)` (= 64) |
| `WHISTLEBLOWER_REWARD_QUOTIENT` | `uint64(2**9)` (= 512) |
| `PROPOSER_REWARD_QUOTIENT` | `uint64(2**3)` (= 8) |
| `INACTIVITY_PENALTY_QUOTIENT` | `uint64(2**26)` (= 67,108,864) |
| `MIN_SLASHING_PENALTY_QUOTIENT` | `uint64(2**7)` (= 128) |
| `PROPORTIONAL_SLASHING_MULTIPLIER` | `uint64(1)` |
| `INACTIVITY_PENALTY_QUOTIENT_ALTAIR` | `uint64(3 * 2**24)` (= 50,331,648) |
| `MIN_SLASHING_PENALTY_QUOTIENT_ALTAIR` | `uint64(2**6)` (= 64) |
| `PROPORTIONAL_SLASHING_MULTIPLIER_ALTAIR` | `uint64(2)` |
| `INACTIVITY_PENALTY_QUOTIENT_BELLATRIX` | `uint64(2**24)` (= 16,777,216) |
| `MIN_SLASHING_PENALTY_QUOTIENT_BELLATRIX` | `uint64(2**5)` (= 32) |
| `PROPORTIONAL_SLASHING_MULTIPLIER_BELLATRIX` | `uint64(3)` |
| `MIN_SLASHING_PENALTY_QUOTIENT_ELECTRA` | `uint64(2**12)` (= 4,096) | *[New in Electra:EIP7251]* |
| `WHISTLEBLOWER_REWARD_QUOTIENT_ELECTRA` | `uint64(2**12)` (= 4,096) | *[New in Electra:EIP7251]* |

### Max operations per block

| Name | Value |
| - | - |
| `MAX_PROPOSER_SLASHINGS` | `2**4` (= 16) |
| `MAX_ATTESTER_SLASHINGS` | `2**1` (= 2) |
| `MAX_ATTESTATIONS` | `2**7` (= 128) |
| `MAX_DEPOSITS` | `2**4` (= 16) |
| `MAX_VOLUNTARY_EXITS` | `2**4` (= 16) |
| `MAX_BLS_TO_EXECUTION_CHANGES` | `2**4` (= 16) |
| `MAX_ATTESTER_SLASHINGS_ELECTRA` | `2**0` (= 1) | *[New in Electra:EIP7549]* |
| `MAX_ATTESTATIONS_ELECTRA` | `2**3` (= 8) | *[New in Electra:EIP7549]* |

### Sync committee

| Name | Value | Unit | Duration |
| - | - | - | - |
| `SYNC_COMMITTEE_SIZE` | `uint64(2**9)` (= 512) | validators | |
| `EPOCHS_PER_SYNC_COMMITTEE_PERIOD` | `uint64(2**8)` (= 256) | epochs | ~27 hours |

### Execution

| Name | Value |
| - | - |
| `MAX_BYTES_PER_TRANSACTION` | `uint64(2**30)` (= 1,073,741,824) |
| `MAX_TRANSACTIONS_PER_PAYLOAD` | `uint64(2**20)` (= 1,048,576) |
| `BYTES_PER_LOGS_BLOOM` | `uint64(2**8)` (= 256) |
| `MAX_EXTRA_DATA_BYTES` | `2**5` (= 32) |
| `MAX_WITHDRAWALS_PER_PAYLOAD` | `uint64(2**4)` (= 16) |
| `MAX_BLOB_COMMITMENTS_PER_BLOCK` | `uint64(2**12)` (= 4096) | *[New in Deneb:EIP4844]* |
| `MAX_BLOBS_PER_BLOCK` | `uint64(6)` | *[New in Deneb:EIP4844]* |
| `MAX_DEPOSIT_REQUESTS_PER_PAYLOAD` | `uint64(2**13)` (= 8,192) | *[New in Electra:EIP6110]* |
| `MAX_WITHDRAWAL_REQUESTS_PER_PAYLOAD` | `uint64(2**4)` (= 16) | *[New in Electra:EIP7002]* |
| `MAX_CONSOLIDATION_REQUESTS_PER_PAYLOAD` | `uint64(2**1)` (= 2) | *[New in Electra:EIP7251]* |

### Withdrawals processing

| Name | Value |
| - | - |
| `MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP` | `16384` (= 2**14) |
| `MAX_PENDING_PARTIALS_PER_WITHDRAWALS_SWEEP` | `uint64(2**3)` (= 8) | *[New in Electra:EIP7002]* |

### Pending deposits processing

| Name | Value |
| - | - |
| `MAX_PENDING_DEPOSITS_PER_EPOCH` | `uint64(2**4)` (= 16) | *[New in Electra:EIP6110]* |

## Configuration

*Note*: The default mainnet configuration values are included here for illustrative purposes.

### Genesis settings

| Name | Value |
| - | - |
| `MIN_GENESIS_ACTIVE_VALIDATOR_COUNT` | `uint64(2**14)` (= 16,384) |
| `MIN_GENESIS_TIME` | `uint64(1606824000)` (Dec 1, 2020, 12pm UTC) |
| `GENESIS_FORK_VERSION` | `Version('0x00000000')` |
| `GENESIS_DELAY` | `uint64(604800)` (7 days) |

### Time parameters

| Name | Value | Unit | Duration |
| - | - | :-: | :-: |
| `SECONDS_PER_SLOT` | `uint64(12)` | seconds | 12 seconds |
| `SECONDS_PER_ETH1_BLOCK` | `uint64(14)` | seconds | 14 seconds |
| `MIN_VALIDATOR_WITHDRAWABILITY_DELAY` | `uint64(2**8)` (= 256) | epochs | ~27 hours |
| `SHARD_COMMITTEE_PERIOD` | `uint64(2**8)` (= 256) | epochs | ~27 hours |
| `ETH1_FOLLOW_DISTANCE` | `uint64(2**11)` (= 2,048) | Eth1 blocks | ~8 hours |

### Validator cycle

| Name | Value |
| - | - |
| `EJECTION_BALANCE` | `Gwei(2**4 * 10**9)` (= 16,000,000,000) |
| `MIN_PER_EPOCH_CHURN_LIMIT` | `uint64(2**2)` (= 4) |
| `CHURN_LIMIT_QUOTIENT` | `uint64(2**16)` (= 65,536) |
| `MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT` | `uint64(2**3)` (= 8) |
| `MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA` | `Gwei(2**7 * 10**9)` (= 128,000,000,000) | *[New in Electra:EIP7251]* |
| `MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT` | `Gwei(2**8 * 10**9)` (= 256,000,000,000) | *[New in Electra:EIP7251]* |

### Inactivity penalties

| Name | Value | Description |
| - | - | - |
| `INACTIVITY_SCORE_BIAS` | `uint64(2**2)` (= 4) | score points per inactive epoch |
| `INACTIVITY_SCORE_RECOVERY_RATE` | `uint64(2**4)` (= 16) | score points per leak-free epoch |

### Transition settings

| Name | Value |
| - | - |
| `TERMINAL_TOTAL_DIFFICULTY` | `58750000000000000000000` (Estimated: Sept 15, 2022) |
| `TERMINAL_BLOCK_HASH` | `Hash32()` |
| `TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH` | `FAR_FUTURE_EPOCH` |

### Execution

| Name | Value |
| - | - |
| `MAX_BLOBS_PER_BLOCK_ELECTRA` | `uint64(9)` | *[New in Electra:EIP7691]* Maximum number of blobs in a single block |

### Blob schedule

*[New in Fulu:EIP7892]* This schedule defines the maximum blobs per block limit for a given epoch.

There MUST NOT exist multiple blob schedule entries with the same epoch value. The epoch value in each entry MUST be greater than or equal to `FULU_FORK_EPOCH`. The maximum blobs per block limit in each entry MUST be less than or equal to `MAX_BLOB_COMMITMENTS_PER_BLOCK`. The blob schedule entries SHOULD be sorted by epoch in ascending order. The blob schedule MAY be empty.

| Epoch | Max Blobs Per Block | Date |
| -----: | ------------------: | -----: |
| 412672 | 15 | December 9, 2025, 02:21:11pm UTC |
| 419072 | 21 | January 7, 2026, 01:01:11am UTC |


## Containers

The following types are SimpleSerialize (SSZ) containers.

*Note*: The definitions are ordered topologically to facilitate execution of the spec.

*Note*: Fields missing in container instantiations default to their zero value.

### Misc dependencies

#### `Fork`

```python
class Fork(Container):
    previous_version: Version
    current_version: Version
    epoch: Epoch  # Epoch of latest fork
```

#### `ForkData`

```python
class ForkData(Container):
    current_version: Version
    genesis_validators_root: Root
```

#### `Checkpoint`

```python
class Checkpoint(Container):
    epoch: Epoch
    root: Root
```

#### `Validator`

```python
class Validator(Container):
    pubkey: BLSPubkey
    withdrawal_credentials: Bytes32  # Commitment to pubkey for withdrawals
    effective_balance: Gwei  # Balance at stake
    slashed: boolean
    # Status epochs
    activation_eligibility_epoch: Epoch  # When criteria for activation were met
    activation_epoch: Epoch
    exit_epoch: Epoch
    withdrawable_epoch: Epoch  # When validator can withdraw funds
```

#### `AttestationData`

```python
class AttestationData(Container):
    slot: Slot
    index: CommitteeIndex
    # LMD GHOST vote
    beacon_block_root: Root
    # FFG vote
    source: Checkpoint
    target: Checkpoint
```

#### `IndexedAttestation`

*[Modified in Electra:EIP7549]* — attesting_indices list capacity extended to `MAX_VALIDATORS_PER_COMMITTEE * MAX_COMMITTEES_PER_SLOT`.

```python
class IndexedAttestation(Container):
    # [Modified in Electra:EIP7549]
    attesting_indices: List[ValidatorIndex, MAX_VALIDATORS_PER_COMMITTEE * MAX_COMMITTEES_PER_SLOT]
    data: AttestationData
    signature: BLSSignature
```

#### `PendingAttestation`

```python
class PendingAttestation(Container):
    aggregation_bits: Bitlist[MAX_VALIDATORS_PER_COMMITTEE]
    data: AttestationData
    inclusion_delay: Slot
    proposer_index: ValidatorIndex
```

#### `Eth1Data`

```python
class Eth1Data(Container):
    deposit_root: Root
    deposit_count: uint64
    block_hash: Hash32
```

#### `HistoricalBatch`

```python
class HistoricalBatch(Container):
    block_roots: Vector[Root, SLOTS_PER_HISTORICAL_ROOT]
    state_roots: Vector[Root, SLOTS_PER_HISTORICAL_ROOT]
```

#### `DepositMessage`

```python
class DepositMessage(Container):
    pubkey: BLSPubkey
    withdrawal_credentials: Bytes32
    amount: Gwei
```

#### `DepositData`

```python
class DepositData(Container):
    pubkey: BLSPubkey
    withdrawal_credentials: Bytes32
    amount: Gwei
    signature: BLSSignature  # Signing over DepositMessage
```

#### `BeaconBlockHeader`

```python
class BeaconBlockHeader(Container):
    slot: Slot
    proposer_index: ValidatorIndex
    parent_root: Root
    state_root: Root
    body_root: Root
```

#### `SigningData`

```python
class SigningData(Container):
    object_root: Root
    domain: Domain
```

#### `ExecutionPayload`

```python
class ExecutionPayload(Container):
    # Execution block header fields
    parent_hash: Hash32
    fee_recipient: ExecutionAddress  # 'beneficiary' in the yellow paper
    state_root: Bytes32
    receipts_root: Bytes32
    logs_bloom: ByteVector[BYTES_PER_LOGS_BLOOM]
    prev_randao: Bytes32  # 'difficulty' in the yellow paper
    block_number: uint64  # 'number' in the yellow paper
    gas_limit: uint64
    gas_used: uint64
    timestamp: uint64
    extra_data: ByteList[MAX_EXTRA_DATA_BYTES]
    base_fee_per_gas: uint256
    # Extra payload fields
    block_hash: Hash32  # Hash of execution block
    transactions: List[Transaction, MAX_TRANSACTIONS_PER_PAYLOAD]
    withdrawals: List[Withdrawal, MAX_WITHDRAWALS_PER_PAYLOAD]
    blob_gas_used: uint64  # [New in Deneb:EIP4844]
    excess_blob_gas: uint64  # [New in Deneb:EIP4844]
```

#### `ExecutionPayloadHeader`

```python
class ExecutionPayloadHeader(Container):
    # Execution block header fields
    parent_hash: Hash32
    fee_recipient: ExecutionAddress
    state_root: Bytes32
    receipts_root: Bytes32
    logs_bloom: ByteVector[BYTES_PER_LOGS_BLOOM]
    prev_randao: Bytes32
    block_number: uint64
    gas_limit: uint64
    gas_used: uint64
    timestamp: uint64
    extra_data: ByteList[MAX_EXTRA_DATA_BYTES]
    base_fee_per_gas: uint256
    # Extra payload fields
    block_hash: Hash32  # Hash of execution block
    transactions_root: Root
    withdrawals_root: Root
    blob_gas_used: uint64  # [New in Deneb:EIP4844]
    excess_blob_gas: uint64  # [New in Deneb:EIP4844]
```

#### `Withdrawal`

```python
class Withdrawal(Container):
    index: WithdrawalIndex
    validator_index: ValidatorIndex
    address: ExecutionAddress
    amount: Gwei
```

#### `BLSToExecutionChange`

```python
class BLSToExecutionChange(Container):
    validator_index: ValidatorIndex
    from_bls_pubkey: BLSPubkey
    to_execution_address: ExecutionAddress
```

#### `SignedBLSToExecutionChange`

```python
class SignedBLSToExecutionChange(Container):
    message: BLSToExecutionChange
    signature: BLSSignature
```

#### `HistoricalSummary`

```python
class HistoricalSummary(Container):
    """
    `HistoricalSummary` matches the components of the phase0 `HistoricalBatch`
    making the two hash_tree_root-compatible.
    """
    block_summary_root: Root
    state_summary_root: Root
```

#### `PendingDeposit`

*[New in Electra:EIP7251]*

```python
class PendingDeposit(Container):
    pubkey: BLSPubkey
    withdrawal_credentials: Bytes32
    amount: Gwei
    signature: BLSSignature
    slot: Slot
```

#### `PendingPartialWithdrawal`

*[New in Electra:EIP7251]*

```python
class PendingPartialWithdrawal(Container):
    validator_index: ValidatorIndex
    amount: Gwei
    withdrawable_epoch: Epoch
```

#### `PendingConsolidation`

*[New in Electra:EIP7251]*

```python
class PendingConsolidation(Container):
    source_index: ValidatorIndex
    target_index: ValidatorIndex
```

#### `DepositRequest`

*[New in Electra:EIP6110]*

```python
class DepositRequest(Container):
    pubkey: BLSPubkey
    withdrawal_credentials: Bytes32
    amount: Gwei
    signature: BLSSignature
    index: uint64
```

#### `WithdrawalRequest`

*[New in Electra:EIP7251:EIP7002]*

```python
class WithdrawalRequest(Container):
    source_address: ExecutionAddress
    validator_pubkey: BLSPubkey
    amount: Gwei
```

#### `ConsolidationRequest`

*[New in Electra:EIP7251]*

```python
class ConsolidationRequest(Container):
    source_address: ExecutionAddress
    source_pubkey: BLSPubkey
    target_pubkey: BLSPubkey
```

#### `ExecutionRequests`

*[New in Electra]*

```python
class ExecutionRequests(Container):
    # [New in Electra:EIP6110]
    deposits: List[DepositRequest, MAX_DEPOSIT_REQUESTS_PER_PAYLOAD]
    # [New in Electra:EIP7002:EIP7251]
    withdrawals: List[WithdrawalRequest, MAX_WITHDRAWAL_REQUESTS_PER_PAYLOAD]
    # [New in Electra:EIP7251]
    consolidations: List[ConsolidationRequest, MAX_CONSOLIDATION_REQUESTS_PER_PAYLOAD]
```

#### `BlobParameters`

*[New in Fulu:EIP7892]*

```python
@dataclass
class BlobParameters:
    epoch: Epoch
    max_blobs_per_block: uint64
```

### Beacon operations

#### `ProposerSlashing`

```python
class ProposerSlashing(Container):
    signed_header_1: SignedBeaconBlockHeader
    signed_header_2: SignedBeaconBlockHeader
```

#### `AttesterSlashing`

*[Modified in Electra:EIP7549]* — uses the updated `IndexedAttestation`.

```python
class AttesterSlashing(Container):
    # [Modified in Electra:EIP7549]
    attestation_1: IndexedAttestation
    # [Modified in Electra:EIP7549]
    attestation_2: IndexedAttestation
```

#### `Attestation`

*[Modified in Electra:EIP7549]* — aggregation_bits capacity extended; committee_bits field added.

```python
class Attestation(Container):
    # [Modified in Electra:EIP7549]
    aggregation_bits: Bitlist[MAX_VALIDATORS_PER_COMMITTEE * MAX_COMMITTEES_PER_SLOT]
    data: AttestationData
    signature: BLSSignature
    # [New in Electra:EIP7549]
    committee_bits: Bitvector[MAX_COMMITTEES_PER_SLOT]
```

#### `SingleAttestation`

*[New in Electra:EIP7549]*

```python
class SingleAttestation(Container):
    committee_index: CommitteeIndex
    attester_index: ValidatorIndex
    data: AttestationData
    signature: BLSSignature
```

#### `Deposit`

```python
class Deposit(Container):
    proof: Vector[Bytes32, DEPOSIT_CONTRACT_TREE_DEPTH + 1]  # Merkle path to deposit root
    data: DepositData
```

#### `VoluntaryExit`

```python
class VoluntaryExit(Container):
    epoch: Epoch  # Earliest epoch when voluntary exit can be processed
    validator_index: ValidatorIndex
```

### Beacon blocks

#### `BeaconBlockBody`

*[Modified in Electra]* — attester_slashings and attestations use Electra limits; execution_requests field added.

```python
class BeaconBlockBody(Container):
    randao_reveal: BLSSignature
    eth1_data: Eth1Data  # Eth1 data vote
    graffiti: Bytes32  # Arbitrary data
    # Operations
    proposer_slashings: List[ProposerSlashing, MAX_PROPOSER_SLASHINGS]
    # [Modified in Electra:EIP7549]
    attester_slashings: List[AttesterSlashing, MAX_ATTESTER_SLASHINGS_ELECTRA]
    # [Modified in Electra:EIP7549]
    attestations: List[Attestation, MAX_ATTESTATIONS_ELECTRA]
    deposits: List[Deposit, MAX_DEPOSITS]
    voluntary_exits: List[SignedVoluntaryExit, MAX_VOLUNTARY_EXITS]
    sync_aggregate: SyncAggregate
    # Execution
    execution_payload: ExecutionPayload
    # Capella operations
    bls_to_execution_changes: List[SignedBLSToExecutionChange, MAX_BLS_TO_EXECUTION_CHANGES]
    blob_kzg_commitments: List[KZGCommitment, MAX_BLOB_COMMITMENTS_PER_BLOCK]  # [New in Deneb:EIP4844]
    # [New in Electra]
    execution_requests: ExecutionRequests
```

#### `BeaconBlock`

```python
class BeaconBlock(Container):
    slot: Slot
    proposer_index: ValidatorIndex
    parent_root: Root
    state_root: Root
    body: BeaconBlockBody
```

### Beacon state

#### `BeaconState`

*[Modified in Fulu:EIP7917]* — proposer_lookahead field added.

```python
class BeaconState(Container):
    # Versioning
    genesis_time: uint64
    genesis_validators_root: Root
    slot: Slot
    fork: Fork
    # History
    latest_block_header: BeaconBlockHeader
    block_roots: Vector[Root, SLOTS_PER_HISTORICAL_ROOT]
    state_roots: Vector[Root, SLOTS_PER_HISTORICAL_ROOT]
    historical_roots: List[Root, HISTORICAL_ROOTS_LIMIT]  # Frozen in Capella, replaced by historical_summaries
    # Eth1
    eth1_data: Eth1Data
    eth1_data_votes: List[Eth1Data, EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH]
    eth1_deposit_index: uint64
    # Registry
    validators: List[Validator, VALIDATOR_REGISTRY_LIMIT]
    balances: List[Gwei, VALIDATOR_REGISTRY_LIMIT]
    # Randomness
    randao_mixes: Vector[Bytes32, EPOCHS_PER_HISTORICAL_VECTOR]
    # Slashings
    slashings: Vector[Gwei, EPOCHS_PER_SLASHINGS_VECTOR]  # Per-epoch sums of slashed effective balances
    # Participation
    previous_epoch_participation: List[ParticipationFlags, VALIDATOR_REGISTRY_LIMIT]  # [Modified in Altair]
    current_epoch_participation: List[ParticipationFlags, VALIDATOR_REGISTRY_LIMIT]  # [Modified in Altair]
    # Finality
    justification_bits: Bitvector[JUSTIFICATION_BITS_LENGTH]  # Bit set for every recent justified epoch
    previous_justified_checkpoint: Checkpoint
    current_justified_checkpoint: Checkpoint
    finalized_checkpoint: Checkpoint
    # Inactivity
    inactivity_scores: List[uint64, VALIDATOR_REGISTRY_LIMIT]  # [New in Altair]
    # Sync
    current_sync_committee: SyncCommittee  # [New in Altair]
    next_sync_committee: SyncCommittee  # [New in Altair]
    # Execution
    latest_execution_payload_header: ExecutionPayloadHeader  # [New in Bellatrix]
    # Withdrawals
    next_withdrawal_index: WithdrawalIndex  # [New in Capella]
    next_withdrawal_validator_index: ValidatorIndex  # [New in Capella]
    # Deep history valid from Capella onwards
    historical_summaries: List[HistoricalSummary, HISTORICAL_ROOTS_LIMIT]  # [New in Capella]
    # [New in Electra:EIP6110]
    deposit_requests_start_index: uint64
    # [New in Electra:EIP7251]
    deposit_balance_to_consume: Gwei
    # [New in Electra:EIP7251]
    exit_balance_to_consume: Gwei
    # [New in Electra:EIP7251]
    earliest_exit_epoch: Epoch
    # [New in Electra:EIP7251]
    consolidation_balance_to_consume: Gwei
    # [New in Electra:EIP7251]
    earliest_consolidation_epoch: Epoch
    # [New in Electra:EIP7251]
    pending_deposits: List[PendingDeposit, PENDING_DEPOSITS_LIMIT]
    # [New in Electra:EIP7251]
    pending_partial_withdrawals: List[PendingPartialWithdrawal, PENDING_PARTIAL_WITHDRAWALS_LIMIT]
    # [New in Electra:EIP7251]
    pending_consolidations: List[PendingConsolidation, PENDING_CONSOLIDATIONS_LIMIT]
    # [New in Fulu:EIP7917]
    proposer_lookahead: Vector[ValidatorIndex, (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH]
```

### Signed envelopes

#### `SignedVoluntaryExit`

```python
class SignedVoluntaryExit(Container):
    message: VoluntaryExit
    signature: BLSSignature
```

#### `SignedBeaconBlock`

```python
class SignedBeaconBlock(Container):
    message: BeaconBlock
    signature: BLSSignature
```

#### `SignedBeaconBlockHeader`

```python
class SignedBeaconBlockHeader(Container):
    message: BeaconBlockHeader
    signature: BLSSignature
```

#### `SyncAggregate`

*[New in Altair]*

```python
class SyncAggregate(Container):
    sync_committee_bits: Bitvector[SYNC_COMMITTEE_SIZE]
    sync_committee_signature: BLSSignature
```

#### `SyncCommittee`

*[New in Altair]*

```python
class SyncCommittee(Container):
    pubkeys: Vector[BLSPubkey, SYNC_COMMITTEE_SIZE]
    aggregate_pubkey: BLSPubkey
```


## Helper functions

*Note*: The definitions below are for specification purposes and are not necessarily optimal implementations.

### Math

#### `integer_squareroot`

```python
def integer_squareroot(n: uint64) -> uint64:
    """
    Return the largest integer ``x`` such that ``x**2 <= n``.
    """
    if n == UINT64_MAX:
        return uint64(4294967295)
    x = n
    y = (x + 1) // 2
    while y < x:
        x = y
        y = (x + n // x) // 2
    return x
```

#### `xor`

```python
def xor(bytes_1: Bytes32, bytes_2: Bytes32) -> Bytes32:
    """
    Return the exclusive-or of two 32-byte strings.
    """
    return Bytes32(a ^ b for a, b in zip(bytes_1, bytes_2))
```

#### `uint_to_bytes`

`def uint_to_bytes(n: uint) -> bytes` is a function for serializing the `uint` type object to bytes in ``ENDIANNESS``-endian. The expected length of the output is the byte-length of the `uint` type.

#### `bytes_to_uint64`

```python
def bytes_to_uint64(data: bytes) -> uint64:
    """
    Return the integer deserialization of ``data`` interpreted as ``ENDIANNESS``-endian.
    """
    return uint64(int.from_bytes(data, ENDIANNESS))
```

#### `saturating_sub`

```python
def saturating_sub(a: int, b: int) -> int:
    """
    Computes a - b, saturating at numeric bounds.
    """
    return a - b if a > b else 0
```

### Crypto

#### `hash`

`def hash(data: bytes) -> Bytes32` is SHA256.

#### `hash_tree_root`

`def hash_tree_root(object: SSZSerializable) -> Root` is a function for hashing objects into a single root by utilizing a hash tree structure, as defined in the SSZ spec.

#### BLS signatures

The [IETF BLS signature draft standard v4](https://tools.ietf.org/html/draft-irtf-cfrg-bls-signature-04) with ciphersuite `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_` defines the following functions:

- `def Sign(privkey: int, message: Bytes) -> BLSSignature`
- `def Verify(pubkey: BLSPubkey, message: Bytes, signature: BLSSignature) -> bool`
- `def Aggregate(signatures: Sequence[BLSSignature]) -> BLSSignature`
- `def FastAggregateVerify(pubkeys: Sequence[BLSPubkey], message: Bytes, signature: BLSSignature) -> bool`
- `def AggregateVerify(pubkeys: Sequence[BLSPubkey], messages: Sequence[Bytes], signature: BLSSignature) -> bool`
- `def KeyValidate(pubkey: BLSPubkey) -> bool`

The above functions are accessed through the `bls` module, e.g. `bls.Verify`.

### Predicates

#### `is_active_validator`

```python
def is_active_validator(validator: Validator, epoch: Epoch) -> bool:
    """
    Check if ``validator`` is active.
    """
    return validator.activation_epoch <= epoch < validator.exit_epoch
```

#### `is_eligible_for_activation_queue`

*[Modified in Electra:EIP7251]* — uses `MIN_ACTIVATION_BALANCE` instead of `MAX_EFFECTIVE_BALANCE`.

```python
def is_eligible_for_activation_queue(validator: Validator) -> bool:
    """
    Check if ``validator`` is eligible to be placed into the activation queue.
    """
    return (
        validator.activation_eligibility_epoch == FAR_FUTURE_EPOCH
        # [Modified in Electra:EIP7251]
        and validator.effective_balance >= MIN_ACTIVATION_BALANCE
    )
```

#### `is_eligible_for_activation`

```python
def is_eligible_for_activation(state: BeaconState, validator: Validator) -> bool:
    """
    Check if ``validator`` is eligible for activation.
    """
    return (
        # Placement in queue is finalized
        validator.activation_eligibility_epoch <= state.finalized_checkpoint.epoch
        # Has not yet been activated
        and validator.activation_epoch == FAR_FUTURE_EPOCH
    )
```

#### `is_slashable_validator`

```python
def is_slashable_validator(validator: Validator, epoch: Epoch) -> bool:
    """
    Check if ``validator`` is slashable.
    """
    return (not validator.slashed) and (validator.activation_epoch <= epoch < validator.withdrawable_epoch)
```

#### `is_slashable_attestation_data`

```python
def is_slashable_attestation_data(data_1: AttestationData, data_2: AttestationData) -> bool:
    """
    Check if ``data_1`` and ``data_2`` are slashable according to Casper FFG rules.
    """
    return (
        # Double vote
        (data_1 \!= data_2 and data_1.target.epoch == data_2.target.epoch) or
        # Surround vote
        (data_1.source.epoch < data_2.source.epoch and data_2.target.epoch < data_1.target.epoch)
    )
```

#### `is_valid_indexed_attestation`

```python
def is_valid_indexed_attestation(state: BeaconState, indexed_attestation: IndexedAttestation) -> bool:
    """
    Check if ``indexed_attestation`` is not empty, has sorted and unique indices and has a valid aggregate signature.
    """
    # Verify indices are sorted and unique
    indices = indexed_attestation.attesting_indices
    if len(indices) == 0 or not indices == sorted(set(indices)):
        return False
    # Verify aggregate signature
    pubkeys = [state.validators[i].pubkey for i in indices]
    domain = get_domain(state, DOMAIN_BEACON_ATTESTER, indexed_attestation.data.target.epoch)
    signing_root = compute_signing_root(indexed_attestation.data, domain)
    return bls.FastAggregateVerify(pubkeys, signing_root, indexed_attestation.signature)
```

#### `is_valid_merkle_branch`

```python
def is_valid_merkle_branch(leaf: Bytes32, branch: Sequence[Bytes32], depth: uint64, index: uint64, root: Root) -> bool:
    """
    Check if ``leaf`` at ``index`` verifies against the Merkle ``root`` and ``branch``.
    """
    value = leaf
    for i in range(depth):
        if index // (2**i) % 2:
            value = hash(branch[i] + value)
        else:
            value = hash(value + branch[i])
    return value == root
```

#### `is_merge_transition_complete`

```python
def is_merge_transition_complete(state: BeaconState) -> bool:
    return state.latest_execution_payload_header \!= ExecutionPayloadHeader()
```

#### `is_merge_transition_block`

```python
def is_merge_transition_block(state: BeaconState, body: BeaconBlockBody) -> bool:
    return not is_merge_transition_complete(state) and body.execution_payload \!= ExecutionPayload()
```

#### `is_execution_enabled`

```python
def is_execution_enabled(state: BeaconState, body: BeaconBlockBody) -> bool:
    return is_merge_transition_block(state, body) or is_merge_transition_complete(state)
```

#### `has_eth1_withdrawal_credential`

```python
def has_eth1_withdrawal_credential(validator: Validator) -> bool:
    """
    Check if ``validator`` has an 0x01 prefixed "eth1" withdrawal credential.
    """
    return validator.withdrawal_credentials[:1] == ETH1_ADDRESS_WITHDRAWAL_PREFIX
```

#### `is_compounding_withdrawal_credential`

*[New in Electra:EIP7251]*

```python
def is_compounding_withdrawal_credential(withdrawal_credentials: Bytes32) -> bool:
    return withdrawal_credentials[:1] == COMPOUNDING_WITHDRAWAL_PREFIX
```

#### `has_compounding_withdrawal_credential`

*[New in Electra:EIP7251]*

```python
def has_compounding_withdrawal_credential(validator: Validator) -> bool:
    """
    Check if ``validator`` has an 0x02 prefixed "compounding" withdrawal credential.
    """
    return is_compounding_withdrawal_credential(validator.withdrawal_credentials)
```

#### `has_execution_withdrawal_credential`

*[New in Electra:EIP7251]*

```python
def has_execution_withdrawal_credential(validator: Validator) -> bool:
    """
    Check if ``validator`` has a 0x01 or 0x02 prefixed withdrawal credential.
    """
    return (
        has_eth1_withdrawal_credential(validator)  # 0x01
        or has_compounding_withdrawal_credential(validator)  # 0x02
    )
```

#### `is_fully_withdrawable_validator`

*[Modified in Electra:EIP7251]* — uses `has_execution_withdrawal_credential`.

```python
def is_fully_withdrawable_validator(validator: Validator, balance: Gwei, epoch: Epoch) -> bool:
    """
    Check if ``validator`` is fully withdrawable.
    """
    return (
        # [Modified in Electra:EIP7251]
        has_execution_withdrawal_credential(validator)
        and validator.withdrawable_epoch <= epoch
        and balance > 0
    )
```

#### `is_partially_withdrawable_validator`

*[Modified in Electra:EIP7251]* — uses `get_max_effective_balance` and `has_execution_withdrawal_credential`.

```python
def is_partially_withdrawable_validator(validator: Validator, balance: Gwei) -> bool:
    """
    Check if ``validator`` is partially withdrawable.
    """
    max_effective_balance = get_max_effective_balance(validator)
    # [Modified in Electra:EIP7251]
    has_max_effective_balance = validator.effective_balance == max_effective_balance
    # [Modified in Electra:EIP7251]
    has_excess_balance = balance > max_effective_balance
    return (
        # [Modified in Electra:EIP7251]
        has_execution_withdrawal_credential(validator)
        and has_max_effective_balance
        and has_excess_balance
    )
```

### Misc

#### `kzg_commitment_to_versioned_hash`

```python
def kzg_commitment_to_versioned_hash(kzg_commitment: KZGCommitment) -> VersionedHash:
    return VERSIONED_HASH_VERSION_KZG + hash(kzg_commitment)[1:]
```

#### `compute_shuffled_index`

```python
def compute_shuffled_index(index: uint64, index_count: uint64, seed: Bytes32) -> uint64:
    """
    Return the shuffled index corresponding to ``seed`` (and ``index_count``).
    """
    assert index < index_count

    # Swap or not (https://link.springer.com/content/pdf/10.1007%2F978-3-642-32009-5_1.pdf)
    # See the 'generalized domain' algorithm on page 3
    for current_round in range(SHUFFLE_ROUND_COUNT):
        pivot = bytes_to_uint64(hash(seed + uint_to_bytes(uint8(current_round)))[0:8]) % index_count
        flip = (pivot + index_count - index) % index_count
        position = max(index, flip)
        source = hash(
            seed
            + uint_to_bytes(uint8(current_round))
            + uint_to_bytes(uint32(position // 256))
        )
        byte = uint8(source[(position % 256) // 8])
        bit = (byte >> (position % 8)) % 2
        index = flip if bit else index

    return index
```

#### `compute_proposer_index`

*[Modified in Electra]* — uses `MAX_EFFECTIVE_BALANCE_ELECTRA` and 16-bit random value.

```python
def compute_proposer_index(
    state: BeaconState, indices: Sequence[ValidatorIndex], seed: Bytes32
) -> ValidatorIndex:
    """
    Return from ``indices`` a random index sampled by effective balance.
    """
    assert len(indices) > 0
    # [Modified in Electra]
    MAX_RANDOM_VALUE = 2**16 - 1
    i = uint64(0)
    total = uint64(len(indices))
    while True:
        candidate_index = indices[compute_shuffled_index(i % total, total, seed)]
        # [Modified in Electra]
        random_bytes = hash(seed + uint_to_bytes(i // 16))
        offset = i % 16 * 2
        random_value = bytes_to_uint64(random_bytes[offset : offset + 2])
        effective_balance = state.validators[candidate_index].effective_balance
        # [Modified in Electra:EIP7251]
        if effective_balance * MAX_RANDOM_VALUE >= MAX_EFFECTIVE_BALANCE_ELECTRA * random_value:
            return candidate_index
        i += 1
```

#### `compute_committee`

```python
def compute_committee(indices: Sequence[ValidatorIndex],
                      seed: Bytes32,
                      index: uint64,
                      count: uint64) -> Sequence[ValidatorIndex]:
    """
    Return the committee corresponding to ``indices``, ``seed``, ``index``, and committee ``count``.
    """
    start = (len(indices) * index) // count
    end = (len(indices) * uint64(index + 1)) // count
    return [indices[compute_shuffled_index(uint64(i), uint64(len(indices)), seed)] for i in range(start, end)]
```

#### `compute_epoch_at_slot`

```python
def compute_epoch_at_slot(slot: Slot) -> Epoch:
    """
    Return the epoch number at ``slot``.
    """
    return Epoch(slot // SLOTS_PER_EPOCH)
```

#### `compute_start_slot_at_epoch`

```python
def compute_start_slot_at_epoch(epoch: Epoch) -> Slot:
    """
    Return the start slot of ``epoch``.
    """
    return Slot(epoch * SLOTS_PER_EPOCH)
```

#### `compute_activation_exit_epoch`

```python
def compute_activation_exit_epoch(epoch: Epoch) -> Epoch:
    """
    Return the epoch during which validator activations and exits initiated in ``epoch`` take effect.
    """
    return Epoch(epoch + 1 + MAX_SEED_LOOKAHEAD)
```

#### `compute_fork_data_root`

```python
def compute_fork_data_root(current_version: Version, genesis_validators_root: Root) -> Root:
    """
    Return the 32-byte fork data root for the ``current_version`` and ``genesis_validators_root``.
    This is used primarily in signature domains to avoid collisions across forks/chains.
    """
    return hash_tree_root(ForkData(
        current_version=current_version,
        genesis_validators_root=genesis_validators_root,
    ))
```

#### `compute_fork_digest`

*[Modified in Fulu:EIP7892]* — updated to account for Blob-Parameters-Only forks.

```python
def compute_fork_digest(
    genesis_validators_root: Root,
    epoch: Epoch,
) -> ForkDigest:
    """
    Return the 4-byte fork digest for the ``genesis_validators_root`` at a given ``epoch``.

    This is a digest primarily used for domain separation on the p2p layer.
    4-bytes suffices for practical separation of forks/chains.
    """
    fork_version = compute_fork_version(epoch)
    base_digest = compute_fork_data_root(fork_version, genesis_validators_root)

    # [Modified in Fulu:EIP7892]
    # Bitmask digest with hash of blob parameters
    blob_parameters = get_blob_parameters(epoch)
    return ForkDigest(
        bytes(
            xor(
                base_digest,
                hash(
                    uint_to_bytes(uint64(blob_parameters.epoch))
                    + uint_to_bytes(uint64(blob_parameters.max_blobs_per_block))
                ),
            )
        )[:4]
    )
```

#### `compute_domain`

```python
def compute_domain(domain_type: DomainType, fork_version: Version=None, genesis_validators_root: Root=None) -> Domain:
    """
    Return the domain for the ``domain_type`` and ``fork_version``.
    """
    if fork_version is None:
        fork_version = GENESIS_FORK_VERSION
    if genesis_validators_root is None:
        genesis_validators_root = Root()  # all bytes zero by default
    fork_data_root = compute_fork_data_root(fork_version, genesis_validators_root)
    return Domain(domain_type + fork_data_root[:28])
```

#### `compute_signing_root`

```python
def compute_signing_root(ssz_object: SSZObject, domain: Domain) -> Root:
    """
    Return the signing root for the corresponding signing data.
    """
    return hash_tree_root(SigningData(
        object_root=hash_tree_root(ssz_object),
        domain=domain,
    ))
```

#### `compute_timestamp_at_slot`

*Note*: This function is unsafe with respect to overflows and underflows.

```python
def compute_timestamp_at_slot(state: BeaconState, slot: Slot) -> uint64:
    slots_since_genesis = slot - GENESIS_SLOT
    return uint64(state.genesis_time + slots_since_genesis * SECONDS_PER_SLOT)
```

#### `add_flag`

```python
def add_flag(flags: ParticipationFlags, flag_index: int) -> ParticipationFlags:
    """
    Return a new ``ParticipationFlags`` adding ``flag_index`` to ``flags``.
    """
    flag = ParticipationFlags(2**flag_index)
    return flags | flag
```

#### `has_flag`

```python
def has_flag(flags: ParticipationFlags, flag_index: int) -> bool:
    """
    Return whether ``flags`` has ``flag_index`` set.
    """
    flag = ParticipationFlags(2**flag_index)
    return flags & flag == flag
```

#### `get_index_for_new_validator`

```python
def get_index_for_new_validator(state: BeaconState) -> ValidatorIndex:
    return ValidatorIndex(len(state.validators))
```

#### `set_or_append_list`

```python
def set_or_append_list(list: List, index: ValidatorIndex, value: Any) -> None:
    if index == len(list):
        list.append(value)
    else:
        list[index] = value
```

#### `get_committee_indices`

*[New in Electra:EIP7549]*

```python
def get_committee_indices(committee_bits: Bitvector) -> Sequence[CommitteeIndex]:
    return [CommitteeIndex(index) for index, bit in enumerate(committee_bits) if bit]
```

#### `get_max_effective_balance`

*[New in Electra:EIP7251]*

```python
def get_max_effective_balance(validator: Validator) -> Gwei:
    """
    Get max effective balance for ``validator``.
    """
    if has_compounding_withdrawal_credential(validator):
        return MAX_EFFECTIVE_BALANCE_ELECTRA
    else:
        return MIN_ACTIVATION_BALANCE
```

#### `get_blob_parameters`

*[New in Fulu:EIP7892]*

```python
def get_blob_parameters(epoch: Epoch) -> BlobParameters:
    """
    Return the blob parameters at a given epoch.
    """
    for entry in sorted(BLOB_SCHEDULE, key=lambda e: e["EPOCH"], reverse=True):
        if epoch >= entry["EPOCH"]:
            return BlobParameters(entry["EPOCH"], entry["MAX_BLOBS_PER_BLOCK"])
    return BlobParameters(ELECTRA_FORK_EPOCH, MAX_BLOBS_PER_BLOCK_ELECTRA)
```

#### `compute_proposer_indices`

*[New in Fulu:EIP7917]*

```python
def compute_proposer_indices(
    state: BeaconState, epoch: Epoch, seed: Bytes32, indices: Sequence[ValidatorIndex]
) -> Vector[ValidatorIndex, SLOTS_PER_EPOCH]:
    """
    Return the proposer indices for the given ``epoch``.
    """
    start_slot = compute_start_slot_at_epoch(epoch)
    seeds = [hash(seed + uint_to_bytes(Slot(start_slot + i))) for i in range(SLOTS_PER_EPOCH)]
    return [compute_proposer_index(state, indices, seed) for seed in seeds]
```


### Beacon state accessors

#### `get_current_epoch`

```python
def get_current_epoch(state: BeaconState) -> Epoch:
    """
    Return the current epoch.
    """
    return compute_epoch_at_slot(state.slot)
```

#### `get_previous_epoch`

```python
def get_previous_epoch(state: BeaconState) -> Epoch:
    """`
    Return the previous epoch (unless the current epoch is ``GENESIS_EPOCH``).
    """
    current_epoch = get_current_epoch(state)
    return GENESIS_EPOCH if current_epoch == GENESIS_EPOCH else Epoch(current_epoch - 1)
```

#### `get_block_root`

```python
def get_block_root(state: BeaconState, epoch: Epoch) -> Root:
    """
    Return the block root at the start of a recent ``epoch``.
    """
    return get_block_root_at_slot(state, compute_start_slot_at_epoch(epoch))
```

#### `get_block_root_at_slot`

```python
def get_block_root_at_slot(state: BeaconState, slot: Slot) -> Root:
    """
    Return the block root at a recent ``slot``.
    """
    assert slot < state.slot <= slot + SLOTS_PER_HISTORICAL_ROOT
    return state.block_roots[slot % SLOTS_PER_HISTORICAL_ROOT]
```

#### `get_randao_mix`

```python
def get_randao_mix(state: BeaconState, epoch: Epoch) -> Bytes32:
    """
    Return the randao mix at a recent ``epoch``.
    """
    return state.randao_mixes[epoch % EPOCHS_PER_HISTORICAL_VECTOR]
```

#### `get_active_validator_indices`

```python
def get_active_validator_indices(state: BeaconState, epoch: Epoch) -> Sequence[ValidatorIndex]:
    """
    Return the sequence of active validator indices at ``epoch``.
    """
    return [ValidatorIndex(i) for i, v in enumerate(state.validators) if is_active_validator(v, epoch)]
```

#### `get_validator_churn_limit`

```python
def get_validator_churn_limit(state: BeaconState) -> uint64:
    """
    Return the validator churn limit for the current epoch.
    """
    active_validator_indices = get_active_validator_indices(state, get_current_epoch(state))
    return max(MIN_PER_EPOCH_CHURN_LIMIT, uint64(len(active_validator_indices)) // CHURN_LIMIT_QUOTIENT)
```

#### `get_seed`

```python
def get_seed(state: BeaconState, epoch: Epoch, domain_type: DomainType) -> Bytes32:
    """
    Return the seed at ``epoch``.
    """
    mix = get_randao_mix(state, Epoch(epoch + EPOCHS_PER_HISTORICAL_VECTOR - MIN_SEED_LOOKAHEAD - 1))  # Avoid underflow
    return hash(domain_type + uint_to_bytes(epoch) + mix)
```

#### `get_committee_count_per_slot`

```python
def get_committee_count_per_slot(state: BeaconState, epoch: Epoch) -> uint64:
    """
    Return the number of committees in each slot for the given ``epoch``.
    """
    return max(uint64(1), min(
        MAX_COMMITTEES_PER_SLOT,
        uint64(len(get_active_validator_indices(state, epoch))) // SLOTS_PER_EPOCH // TARGET_COMMITTEE_SIZE,
    ))
```

#### `get_beacon_committee`

```python
def get_beacon_committee(state: BeaconState, slot: Slot, index: CommitteeIndex) -> Sequence[ValidatorIndex]:
    """
    Return the beacon committee at ``slot`` for ``index``.
    """
    epoch = compute_epoch_at_slot(slot)
    committees_per_slot = get_committee_count_per_slot(state, epoch)
    return compute_committee(
        indices=get_active_validator_indices(state, epoch),
        seed=get_seed(state, epoch, DOMAIN_BEACON_ATTESTER),
        index=(slot % SLOTS_PER_EPOCH) * committees_per_slot + index,
        count=committees_per_slot * SLOTS_PER_EPOCH,
    )
```

#### `get_beacon_proposer_index`

*[Modified in Fulu:EIP7917]* — reads from pre-calculated `proposer_lookahead`.

```python
def get_beacon_proposer_index(state: BeaconState) -> ValidatorIndex:
    """
    Return the beacon proposer index at the current slot.
    """
    return state.proposer_lookahead[state.slot % SLOTS_PER_EPOCH]
```

#### `get_beacon_proposer_indices`

*[New in Fulu:EIP7917]*

```python
def get_beacon_proposer_indices(
    state: BeaconState, epoch: Epoch
) -> Vector[ValidatorIndex, SLOTS_PER_EPOCH]:
    """
    Return the proposer indices for the given ``epoch``.
    """
    indices = get_active_validator_indices(state, epoch)
    seed = get_seed(state, epoch, DOMAIN_BEACON_PROPOSER)
    return compute_proposer_indices(state, epoch, seed, indices)
```

#### `get_total_balance`

```python
def get_total_balance(state: BeaconState, indices: Set[ValidatorIndex]) -> Gwei:
    """
    Return the combined effective balance of the ``indices``.
    ``EFFECTIVE_BALANCE_INCREMENT`` Gwei minimum to avoid divisions by zero.
    Math safe up to ~10B ETH, after which this overflows uint64.
    """
    return Gwei(max(EFFECTIVE_BALANCE_INCREMENT, sum([state.validators[index].effective_balance for index in indices])))
```

#### `get_total_active_balance`

```python
def get_total_active_balance(state: BeaconState) -> Gwei:
    """
    Return the combined effective balance of the active validators.
    Note: ``get_total_balance`` returns ``EFFECTIVE_BALANCE_INCREMENT`` Gwei minimum to avoid divisions by zero.
    """
    return get_total_balance(state, set(get_active_validator_indices(state, get_current_epoch(state))))
```

#### `get_domain`

```python
def get_domain(state: BeaconState, domain_type: DomainType, epoch: Epoch=None) -> Domain:
    """
    Return the signature domain (fork version concatenated with domain type) of a message.
    """
    epoch = get_current_epoch(state) if epoch is None else epoch
    fork_version = state.fork.previous_version if epoch < state.fork.epoch else state.fork.current_version
    return compute_domain(domain_type, fork_version, state.genesis_validators_root)
```

#### `get_indexed_attestation`

```python
def get_indexed_attestation(state: BeaconState, attestation: Attestation) -> IndexedAttestation:
    """
    Return the indexed attestation corresponding to ``attestation``.
    """
    attesting_indices = get_attesting_indices(state, attestation)

    return IndexedAttestation(
        attesting_indices=sorted(attesting_indices),
        data=attestation.data,
        signature=attestation.signature,
    )
```

#### `get_attesting_indices`

*[Modified in Electra:EIP7549]* — supports committee_bits for multi-committee attestations.

```python
def get_attesting_indices(state: BeaconState, attestation: Attestation) -> Set[ValidatorIndex]:
    """
    Return the set of attesting indices corresponding to ``aggregation_bits`` and ``committee_bits``.
    """
    output: Set[ValidatorIndex] = set()
    committee_indices = get_committee_indices(attestation.committee_bits)
    committee_offset = 0
    for committee_index in committee_indices:
        committee = get_beacon_committee(state, attestation.data.slot, committee_index)
        committee_attesters = set(
            attester_index
            for i, attester_index in enumerate(committee)
            if attestation.aggregation_bits[committee_offset + i]
        )
        output = output.union(committee_attesters)

        committee_offset += len(committee)

    return output
```

#### `get_next_sync_committee_indices`

*[Modified in Electra:EIP7251]* — uses `MAX_EFFECTIVE_BALANCE_ELECTRA` and 16-bit random value.

```python
def get_next_sync_committee_indices(state: BeaconState) -> Sequence[ValidatorIndex]:
    """
    Return the sync committee indices, with possible duplicates, for the next sync committee.
    """
    epoch = Epoch(get_current_epoch(state) + 1)

    # [Modified in Electra]
    MAX_RANDOM_VALUE = 2**16 - 1
    active_validator_indices = get_active_validator_indices(state, epoch)
    active_validator_count = uint64(len(active_validator_indices))
    seed = get_seed(state, epoch, DOMAIN_SYNC_COMMITTEE)
    i = uint64(0)
    sync_committee_indices: List[ValidatorIndex] = []
    while len(sync_committee_indices) < SYNC_COMMITTEE_SIZE:
        shuffled_index = compute_shuffled_index(
            uint64(i % active_validator_count), active_validator_count, seed
        )
        candidate_index = active_validator_indices[shuffled_index]
        # [Modified in Electra]
        random_bytes = hash(seed + uint_to_bytes(i // 16))
        offset = i % 16 * 2
        random_value = bytes_to_uint64(random_bytes[offset : offset + 2])
        effective_balance = state.validators[candidate_index].effective_balance
        # [Modified in Electra:EIP7251]
        if effective_balance * MAX_RANDOM_VALUE >= MAX_EFFECTIVE_BALANCE_ELECTRA * random_value:
            sync_committee_indices.append(candidate_index)
        i += 1
    return sync_committee_indices
```

#### `get_next_sync_committee`

*Note*: The function `get_next_sync_committee` should only be called at sync committee period boundaries and when upgrading the state.

```python
def get_next_sync_committee(state: BeaconState) -> SyncCommittee:
    """
    Return the next sync committee, with possible pubkey duplicates.
    """
    indices = get_next_sync_committee_indices(state)
    pubkeys = [state.validators[index].pubkey for index in indices]
    aggregate_pubkey = eth_aggregate_pubkeys(pubkeys)
    return SyncCommittee(pubkeys=pubkeys, aggregate_pubkey=aggregate_pubkey)
```

#### `get_base_reward_per_increment`

```python
def get_base_reward_per_increment(state: BeaconState) -> Gwei:
    return Gwei(EFFECTIVE_BALANCE_INCREMENT * BASE_REWARD_FACTOR // integer_squareroot(get_total_active_balance(state)))
```

#### `get_base_reward`

*Note*: On average an optimally performing validator earns one base reward per epoch.

```python
def get_base_reward(state: BeaconState, index: ValidatorIndex) -> Gwei:
    """
    Return the base reward for the validator defined by ``index`` with respect to the current ``state``.
    """
    increments = state.validators[index].effective_balance // EFFECTIVE_BALANCE_INCREMENT
    return Gwei(increments * get_base_reward_per_increment(state))
```

#### `get_unslashed_participating_indices`

```python
def get_unslashed_participating_indices(state: BeaconState, flag_index: int, epoch: Epoch) -> Set[ValidatorIndex]:
    """
    Return the set of validator indices that are both active and unslashed for the given ``flag_index`` and ``epoch``.
    """
    assert epoch in (get_previous_epoch(state), get_current_epoch(state))
    if epoch == get_current_epoch(state):
        epoch_participation = state.current_epoch_participation
    else:
        epoch_participation = state.previous_epoch_participation
    active_validator_indices = get_active_validator_indices(state, epoch)
    participating_indices = [i for i in active_validator_indices if has_flag(epoch_participation[i], flag_index)]
    return set(filter(lambda index: not state.validators[index].slashed, participating_indices))
```

#### `get_attestation_participation_flag_indices`

```python
def get_attestation_participation_flag_indices(state: BeaconState,
                                               data: AttestationData,
                                               inclusion_delay: uint64) -> Sequence[int]:
    """
    Return the flag indices that are satisfied by an attestation.
    """
    if data.target.epoch == get_current_epoch(state):
        justified_checkpoint = state.current_justified_checkpoint
    else:
        justified_checkpoint = state.previous_justified_checkpoint

    # Matching roots
    is_matching_source = data.source == justified_checkpoint
    is_matching_target = is_matching_source and data.target.root == get_block_root(state, data.target.epoch)
    is_matching_head = is_matching_target and data.beacon_block_root == get_block_root_at_slot(state, data.slot)
    assert is_matching_source

    participation_flag_indices = []
    if is_matching_source and inclusion_delay <= integer_squareroot(SLOTS_PER_EPOCH):
        participation_flag_indices.append(TIMELY_SOURCE_FLAG_INDEX)
    if is_matching_target:  # [Modified in Deneb:EIP7045]
        participation_flag_indices.append(TIMELY_TARGET_FLAG_INDEX)
    if is_matching_head and inclusion_delay == MIN_ATTESTATION_INCLUSION_DELAY:
        participation_flag_indices.append(TIMELY_HEAD_FLAG_INDEX)

    return participation_flag_indices
```

#### `get_flag_index_deltas`

```python
def get_flag_index_deltas(state: BeaconState, flag_index: int) -> Tuple[Sequence[Gwei], Sequence[Gwei]]:
    """
    Return the deltas for a given ``flag_index`` by scanning through the participation flags.
    """
    rewards = [Gwei(0)] * len(state.validators)
    penalties = [Gwei(0)] * len(state.validators)
    previous_epoch = get_previous_epoch(state)
    unslashed_participating_indices = get_unslashed_participating_indices(state, flag_index, previous_epoch)
    weight = PARTICIPATION_FLAG_WEIGHTS[flag_index]
    unslashed_participating_balance = get_total_balance(state, unslashed_participating_indices)
    unslashed_participating_increments = unslashed_participating_balance // EFFECTIVE_BALANCE_INCREMENT
    active_increments = get_total_active_balance(state) // EFFECTIVE_BALANCE_INCREMENT
    for index in get_eligible_validator_indices(state):
        base_reward = get_base_reward(state, index)
        if index in unslashed_participating_indices:
            if not is_in_inactivity_leak(state):
                reward_numerator = base_reward * weight * unslashed_participating_increments
                rewards[index] += Gwei(reward_numerator // (active_increments * WEIGHT_DENOMINATOR))
        elif flag_index \!= TIMELY_HEAD_FLAG_INDEX:
            penalties[index] += Gwei(base_reward * weight // WEIGHT_DENOMINATOR)
    return rewards, penalties
```

#### `get_inactivity_penalty_deltas`

```python
def get_inactivity_penalty_deltas(state: BeaconState) -> Tuple[Sequence[Gwei], Sequence[Gwei]]:
    """
    Return the inactivity penalty deltas by considering timely target participation flags and inactivity scores.
    Uses INACTIVITY_PENALTY_QUOTIENT_BELLATRIX (active from Bellatrix onwards).
    """
    rewards = [Gwei(0) for _ in range(len(state.validators))]
    penalties = [Gwei(0) for _ in range(len(state.validators))]
    previous_epoch = get_previous_epoch(state)
    matching_target_indices = get_unslashed_participating_indices(state, TIMELY_TARGET_FLAG_INDEX, previous_epoch)
    for index in get_eligible_validator_indices(state):
        if index not in matching_target_indices:
            penalty_numerator = state.validators[index].effective_balance * state.inactivity_scores[index]
            penalty_denominator = INACTIVITY_SCORE_BIAS * INACTIVITY_PENALTY_QUOTIENT_BELLATRIX
            penalties[index] += Gwei(penalty_numerator // penalty_denominator)
    return rewards, penalties
```

#### `get_validator_activation_churn_limit`

```python
def get_validator_activation_churn_limit(state: BeaconState) -> uint64:
    """
    Return the validator activation churn limit for the current epoch.
    """
    return min(MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT, get_validator_churn_limit(state))
```

#### `get_balance_churn_limit`

*[New in Electra:EIP7251]*

```python
def get_balance_churn_limit(state: BeaconState) -> Gwei:
    """
    Return the churn limit for the current epoch.
    """
    churn = max(
        MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA, get_total_active_balance(state) // CHURN_LIMIT_QUOTIENT
    )
    return churn - churn % EFFECTIVE_BALANCE_INCREMENT
```

#### `get_activation_exit_churn_limit`

*[New in Electra:EIP7251]*

```python
def get_activation_exit_churn_limit(state: BeaconState) -> Gwei:
    """
    Return the churn limit for the current epoch dedicated to activations and exits.
    """
    return min(MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT, get_balance_churn_limit(state))
```

#### `get_consolidation_churn_limit`

*[New in Electra:EIP7251]*

```python
def get_consolidation_churn_limit(state: BeaconState) -> Gwei:
    return get_balance_churn_limit(state) - get_activation_exit_churn_limit(state)
```

#### `get_pending_balance_to_withdraw`

*[New in Electra:EIP7251]*

```python
def get_pending_balance_to_withdraw(state: BeaconState, validator_index: ValidatorIndex) -> Gwei:
    return sum(
        withdrawal.amount
        for withdrawal in state.pending_partial_withdrawals
        if withdrawal.validator_index == validator_index
    )
```

### Beacon state mutators

#### `increase_balance`

```python
def increase_balance(state: BeaconState, index: ValidatorIndex, delta: Gwei) -> None:
    """
    Increase the validator balance at index ``index`` by ``delta``.
    """
    state.balances[index] += delta
```

#### `decrease_balance`

```python
def decrease_balance(state: BeaconState, index: ValidatorIndex, delta: Gwei) -> None:
    """
    Decrease the validator balance at index ``index`` by ``delta``, with underflow protection.
    """
    state.balances[index] = 0 if delta > state.balances[index] else state.balances[index] - delta
```

#### `initiate_validator_exit`

*[Modified in Electra:EIP7251]* — uses `compute_exit_epoch_and_update_churn`.

```python
def initiate_validator_exit(state: BeaconState, index: ValidatorIndex) -> None:
    """
    Initiate the exit of the validator with index ``index``.
    """
    # Return if validator already initiated exit
    validator = state.validators[index]
    if validator.exit_epoch \!= FAR_FUTURE_EPOCH:
        return

    # Compute exit queue epoch [Modified in Electra:EIP7251]
    exit_queue_epoch = compute_exit_epoch_and_update_churn(state, validator.effective_balance)

    # Set validator exit epoch and withdrawable epoch
    validator.exit_epoch = exit_queue_epoch
    validator.withdrawable_epoch = Epoch(validator.exit_epoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY)
```

#### `slash_validator`

*[Modified in Electra:EIP7251]* — uses `MIN_SLASHING_PENALTY_QUOTIENT_ELECTRA` and `WHISTLEBLOWER_REWARD_QUOTIENT_ELECTRA`.

```python
def slash_validator(
    state: BeaconState, slashed_index: ValidatorIndex, whistleblower_index: ValidatorIndex = None
) -> None:
    """
    Slash the validator with index ``slashed_index``.
    """
    epoch = get_current_epoch(state)
    initiate_validator_exit(state, slashed_index)
    validator = state.validators[slashed_index]
    validator.slashed = True
    validator.withdrawable_epoch = max(
        validator.withdrawable_epoch, Epoch(epoch + EPOCHS_PER_SLASHINGS_VECTOR)
    )
    state.slashings[epoch % EPOCHS_PER_SLASHINGS_VECTOR] += validator.effective_balance
    # [Modified in Electra:EIP7251]
    slashing_penalty = validator.effective_balance // MIN_SLASHING_PENALTY_QUOTIENT_ELECTRA
    decrease_balance(state, slashed_index, slashing_penalty)

    # Apply proposer and whistleblower rewards
    proposer_index = get_beacon_proposer_index(state)
    if whistleblower_index is None:
        whistleblower_index = proposer_index
    # [Modified in Electra:EIP7251]
    whistleblower_reward = Gwei(
        validator.effective_balance // WHISTLEBLOWER_REWARD_QUOTIENT_ELECTRA
    )
    proposer_reward = Gwei(whistleblower_reward * PROPOSER_WEIGHT // WEIGHT_DENOMINATOR)
    increase_balance(state, proposer_index, proposer_reward)
    increase_balance(state, whistleblower_index, Gwei(whistleblower_reward - proposer_reward))
```

#### `switch_to_compounding_validator`

*[New in Electra:EIP7251]*

```python
def switch_to_compounding_validator(state: BeaconState, index: ValidatorIndex) -> None:
    validator = state.validators[index]
    validator.withdrawal_credentials = (
        COMPOUNDING_WITHDRAWAL_PREFIX + validator.withdrawal_credentials[1:]
    )
    queue_excess_active_balance(state, index)
```

#### `queue_excess_active_balance`

*[New in Electra:EIP7251]*

```python
def queue_excess_active_balance(state: BeaconState, index: ValidatorIndex) -> None:
    balance = state.balances[index]
    if balance > MIN_ACTIVATION_BALANCE:
        excess_balance = balance - MIN_ACTIVATION_BALANCE
        state.balances[index] = MIN_ACTIVATION_BALANCE
        validator = state.validators[index]
        # Use bls.G2_POINT_AT_INFINITY as a signature field placeholder
        # and GENESIS_SLOT to distinguish from a pending deposit request
        state.pending_deposits.append(
            PendingDeposit(
                pubkey=validator.pubkey,
                withdrawal_credentials=validator.withdrawal_credentials,
                amount=excess_balance,
                signature=bls.G2_POINT_AT_INFINITY,
                slot=GENESIS_SLOT,
            )
        )
```

#### `compute_exit_epoch_and_update_churn`

*[New in Electra:EIP7251]*

```python
def compute_exit_epoch_and_update_churn(state: BeaconState, exit_balance: Gwei) -> Epoch:
    earliest_exit_epoch = max(
        state.earliest_exit_epoch, compute_activation_exit_epoch(get_current_epoch(state))
    )
    per_epoch_churn = get_activation_exit_churn_limit(state)
    # New epoch for exits.
    if state.earliest_exit_epoch < earliest_exit_epoch:
        exit_balance_to_consume = per_epoch_churn
    else:
        exit_balance_to_consume = state.exit_balance_to_consume

    # Exit doesn't fit in the current earliest epoch.
    if exit_balance > exit_balance_to_consume:
        balance_to_process = exit_balance - exit_balance_to_consume
        additional_epochs = (balance_to_process - 1) // per_epoch_churn + 1
        earliest_exit_epoch += additional_epochs
        exit_balance_to_consume += additional_epochs * per_epoch_churn

    # Consume the balance and update state variables.
    state.exit_balance_to_consume = exit_balance_to_consume - exit_balance
    state.earliest_exit_epoch = earliest_exit_epoch

    return state.earliest_exit_epoch
```

#### `compute_consolidation_epoch_and_update_churn`

*[New in Electra:EIP7251]*

```python
def compute_consolidation_epoch_and_update_churn(
    state: BeaconState, consolidation_balance: Gwei
) -> Epoch:
    earliest_consolidation_epoch = max(
        state.earliest_consolidation_epoch, compute_activation_exit_epoch(get_current_epoch(state))
    )
    per_epoch_consolidation_churn = get_consolidation_churn_limit(state)
    # New epoch for consolidations.
    if state.earliest_consolidation_epoch < earliest_consolidation_epoch:
        consolidation_balance_to_consume = per_epoch_consolidation_churn
    else:
        consolidation_balance_to_consume = state.consolidation_balance_to_consume

    # Consolidation doesn't fit in the current earliest epoch.
    if consolidation_balance > consolidation_balance_to_consume:
        balance_to_process = consolidation_balance - consolidation_balance_to_consume
        additional_epochs = (balance_to_process - 1) // per_epoch_consolidation_churn + 1
        earliest_consolidation_epoch += additional_epochs
        consolidation_balance_to_consume += additional_epochs * per_epoch_consolidation_churn

    # Consume the balance and update state variables.
    state.consolidation_balance_to_consume = (
        consolidation_balance_to_consume - consolidation_balance
    )
    state.earliest_consolidation_epoch = earliest_consolidation_epoch

    return state.earliest_consolidation_epoch
```


## Genesis

Before the Ethereum beacon chain genesis has been triggered, and for every Ethereum execution block, let `candidate_state = initialize_beacon_state_from_eth1(eth1_block_hash, eth1_timestamp, deposits)` where:

- `eth1_block_hash` is the hash of the Ethereum execution block
- `eth1_timestamp` is the Unix timestamp corresponding to `eth1_block_hash`
- `deposits` is the sequence of all deposits, ordered chronologically, up to (and including) the block with hash `eth1_block_hash`

Execution blocks must only be considered once they are at least `SECONDS_PER_ETH1_BLOCK * ETH1_FOLLOW_DISTANCE` seconds old. Due to this constraint, if `GENESIS_DELAY < SECONDS_PER_ETH1_BLOCK * ETH1_FOLLOW_DISTANCE`, then the `genesis_time` can happen before the time/state is first known. Values should be configured to avoid this case.

```python
def initialize_beacon_state_from_eth1(eth1_block_hash: Hash32,
                                      eth1_timestamp: uint64,
                                      deposits: Sequence[Deposit],
                                      execution_payload_header: ExecutionPayloadHeader=ExecutionPayloadHeader()
                                      ) -> BeaconState:
    fork = Fork(
        previous_version=FULU_FORK_VERSION,  # [Modified in Fulu] for testing only
        current_version=FULU_FORK_VERSION,  # [Modified in Fulu]
        epoch=GENESIS_EPOCH,
    )
    state = BeaconState(
        genesis_time=eth1_timestamp + GENESIS_DELAY,
        fork=fork,
        eth1_data=Eth1Data(block_hash=eth1_block_hash, deposit_count=uint64(len(deposits))),
        latest_block_header=BeaconBlockHeader(body_root=hash_tree_root(BeaconBlockBody())),
        randao_mixes=[eth1_block_hash] * EPOCHS_PER_HISTORICAL_VECTOR,  # Seed RANDAO with Eth1 entropy
    )

    # Process deposits
    leaves = list(map(lambda deposit: deposit.data, deposits))
    for index, deposit in enumerate(deposits):
        deposit_data_list = List[DepositData, 2**DEPOSIT_CONTRACT_TREE_DEPTH](*leaves[:index + 1])
        state.eth1_data.deposit_root = hash_tree_root(deposit_data_list)
        process_deposit(state, deposit)

    # Process activations
    for index, validator in enumerate(state.validators):
        balance = state.balances[index]
        validator.effective_balance = min(balance - balance % EFFECTIVE_BALANCE_INCREMENT, MAX_EFFECTIVE_BALANCE)
        if validator.effective_balance == MAX_EFFECTIVE_BALANCE:
            validator.activation_eligibility_epoch = GENESIS_EPOCH
            validator.activation_epoch = GENESIS_EPOCH

    # Set genesis validators root for domain separation and chain versioning
    state.genesis_validators_root = hash_tree_root(state.validators)

    # Fill in sync committees
    # Note: A duplicate committee is assigned for the current and next committee at genesis
    state.current_sync_committee = get_next_sync_committee(state)
    state.next_sync_committee = get_next_sync_committee(state)

    # Initialize the execution payload header
    # If empty, will initialize a chain that has not yet gone through the Merge transition
    state.latest_execution_payload_header = execution_payload_header

    # [New in Electra:EIP6110]
    state.deposit_requests_start_index = UNSET_DEPOSIT_REQUESTS_START_INDEX

    # [New in Fulu:EIP7917] Initialize the proposer lookahead
    # Note: this initializes lookahead for the current and next epoch at genesis
    current_epoch = get_current_epoch(state)
    for epoch_offset in range(MIN_SEED_LOOKAHEAD + 1):
        epoch = Epoch(current_epoch + epoch_offset)
        proposers = get_beacon_proposer_indices(state, epoch)
        start = epoch_offset * SLOTS_PER_EPOCH
        state.proposer_lookahead[start : start + SLOTS_PER_EPOCH] = proposers

    return state
```

### Genesis state

Let `genesis_state = candidate_state` whenever `is_valid_genesis_state(candidate_state) is True` for the first time.

```python
def is_valid_genesis_state(state: BeaconState) -> bool:
    if state.genesis_time < MIN_GENESIS_TIME:
        return False
    if len(get_active_validator_indices(state, GENESIS_EPOCH)) < MIN_GENESIS_ACTIVE_VALIDATOR_COUNT:
        return False
    return True
```

### Genesis block

Let `genesis_block = BeaconBlock(state_root=hash_tree_root(genesis_state))`.

## Beacon chain state transition function

The post-state corresponding to a pre-state `state` and a signed block `signed_block` is defined as `state_transition(state, signed_block)`. State transitions that trigger an unhandled exception (e.g. a failed `assert` or an out-of-range list access) are considered invalid. State transitions that cause a `uint64` overflow or underflow are also considered invalid.

```python
def state_transition(state: BeaconState, signed_block: SignedBeaconBlock, validate_result: bool=True) -> None:
    block = signed_block.message
    # Process slots (including those with no blocks) since block
    process_slots(state, block.slot)
    # Verify signature
    if validate_result:
        assert verify_block_signature(state, signed_block)
    # Process block
    process_block(state, block)
    # Verify state root
    if validate_result:
        assert block.state_root == hash_tree_root(state)
```

```python
def verify_block_signature(state: BeaconState, signed_block: SignedBeaconBlock) -> bool:
    proposer = state.validators[signed_block.message.proposer_index]
    signing_root = compute_signing_root(signed_block.message, get_domain(state, DOMAIN_BEACON_PROPOSER))
    return bls.Verify(proposer.pubkey, signing_root, signed_block.signature)
```

```python
def process_slots(state: BeaconState, slot: Slot) -> None:
    assert state.slot < slot
    while state.slot < slot:
        process_slot(state)
        # Process epoch on the start slot of the next epoch
        if (state.slot + 1) % SLOTS_PER_EPOCH == 0:
            process_epoch(state)
        state.slot = Slot(state.slot + 1)
```

```python
def process_slot(state: BeaconState) -> None:
    # Cache state root
    previous_state_root = hash_tree_root(state)
    state.state_roots[state.slot % SLOTS_PER_HISTORICAL_ROOT] = previous_state_root
    # Cache latest block header state root
    if state.latest_block_header.state_root == Bytes32():
        state.latest_block_header.state_root = previous_state_root
    # Cache block root
    previous_block_root = hash_tree_root(state.latest_block_header)
    state.block_roots[state.slot % SLOTS_PER_HISTORICAL_ROOT] = previous_block_root
```

### Epoch processing

*[Modified in Fulu:EIP7917]* — `process_proposer_lookahead` added.

```python
def process_epoch(state: BeaconState) -> None:
    process_justification_and_finalization(state)
    process_inactivity_updates(state)
    process_rewards_and_penalties(state)
    process_registry_updates(state)
    process_slashings(state)
    process_eth1_data_reset(state)
    # [New in Electra:EIP7251]
    process_pending_deposits(state)
    # [New in Electra:EIP7251]
    process_pending_consolidations(state)
    # [Modified in Electra:EIP7251]
    process_effective_balance_updates(state)
    process_slashings_reset(state)
    process_randao_mixes_reset(state)
    process_historical_summaries_update(state)
    process_participation_flag_updates(state)
    process_sync_committee_updates(state)
    # [New in Fulu:EIP7917]
    process_proposer_lookahead(state)
```

#### Helper functions

```python
def get_matching_source_attestations(state: BeaconState, epoch: Epoch) -> Sequence[PendingAttestation]:
    assert epoch in (get_previous_epoch(state), get_current_epoch(state))
    return state.current_epoch_attestations if epoch == get_current_epoch(state) else state.previous_epoch_attestations
```

```python
def get_matching_target_attestations(state: BeaconState, epoch: Epoch) -> Sequence[PendingAttestation]:
    return [
        a for a in get_matching_source_attestations(state, epoch)
        if a.data.target.root == get_block_root(state, epoch)
    ]
```

```python
def get_matching_head_attestations(state: BeaconState, epoch: Epoch) -> Sequence[PendingAttestation]:
    return [
        a for a in get_matching_target_attestations(state, epoch)
        if a.data.beacon_block_root == get_block_root_at_slot(state, a.data.slot)
    ]
```

```python
def get_unslashed_attesting_indices(state: BeaconState,
                                    attestations: Sequence[PendingAttestation]) -> Set[ValidatorIndex]:
    output = set()  # type: Set[ValidatorIndex]
    for a in attestations:
        output = output.union(get_attesting_indices(state, a.data, a.aggregation_bits))
    return set(filter(lambda index: not state.validators[index].slashed, output))
```

```python
def get_attesting_balance(state: BeaconState, attestations: Sequence[PendingAttestation]) -> Gwei:
    """
    Return the combined effective balance of the set of unslashed validators participating in ``attestations``.
    Note: ``get_total_balance`` returns ``EFFECTIVE_BALANCE_INCREMENT`` Gwei minimum to avoid divisions by zero.
    """
    return get_total_balance(state, get_unslashed_attesting_indices(state, attestations))
```

```python
def get_finality_delay(state: BeaconState) -> uint64:
    return get_previous_epoch(state) - state.finalized_checkpoint.epoch
```

```python
def is_in_inactivity_leak(state: BeaconState) -> bool:
    return get_finality_delay(state) > MIN_EPOCHS_TO_INACTIVITY_PENALTY
```

```python
def get_eligible_validator_indices(state: BeaconState) -> Sequence[ValidatorIndex]:
    previous_epoch = get_previous_epoch(state)
    return [
        ValidatorIndex(index) for index, v in enumerate(state.validators)
        if is_active_validator(v, previous_epoch) or (v.slashed and previous_epoch + 1 < v.withdrawable_epoch)
    ]
```

#### Justification and finalization

##### `process_justification_and_finalization`

```python
def process_justification_and_finalization(state: BeaconState) -> None:
    # Initial FFG checkpoint values have a `0x00` stub for `root`.
    # Skip FFG updates in the first two epochs to avoid corner cases that might result in modifying this stub.
    if get_current_epoch(state) <= GENESIS_EPOCH + 1:
        return
    previous_indices = get_unslashed_participating_indices(state, TIMELY_TARGET_FLAG_INDEX, get_previous_epoch(state))
    current_indices = get_unslashed_participating_indices(state, TIMELY_TARGET_FLAG_INDEX, get_current_epoch(state))
    total_active_balance = get_total_active_balance(state)
    previous_target_balance = get_total_balance(state, previous_indices)
    current_target_balance = get_total_balance(state, current_indices)
    weigh_justification_and_finalization(state, total_active_balance, previous_target_balance, current_target_balance)
```

##### `weigh_justification_and_finalization`

```python
def weigh_justification_and_finalization(state: BeaconState,
                                         total_active_balance: Gwei,
                                         previous_epoch_target_balance: Gwei,
                                         current_epoch_target_balance: Gwei) -> None:
    previous_epoch = get_previous_epoch(state)
    current_epoch = get_current_epoch(state)
    old_previous_justified_checkpoint = state.previous_justified_checkpoint
    old_current_justified_checkpoint = state.current_justified_checkpoint

    # Process justifications
    state.previous_justified_checkpoint = state.current_justified_checkpoint
    state.justification_bits[1:] = state.justification_bits[:JUSTIFICATION_BITS_LENGTH - 1]
    state.justification_bits[0] = 0b0
    if previous_epoch_target_balance * 3 >= total_active_balance * 2:
        state.current_justified_checkpoint = Checkpoint(epoch=previous_epoch,
                                                        root=get_block_root(state, previous_epoch))
        state.justification_bits[1] = 0b1
    if current_epoch_target_balance * 3 >= total_active_balance * 2:
        state.current_justified_checkpoint = Checkpoint(epoch=current_epoch,
                                                        root=get_block_root(state, current_epoch))
        state.justification_bits[0] = 0b1

    # Process finalizations
    bits = state.justification_bits
    # The 2nd/3rd/4th most recent epochs are justified, the 2nd using the 4th as source
    if all(bits[1:4]) and old_previous_justified_checkpoint.epoch + 3 == current_epoch:
        state.finalized_checkpoint = old_previous_justified_checkpoint
    # The 2nd/3rd most recent epochs are justified, the 2nd using the 3rd as source
    if all(bits[1:3]) and old_previous_justified_checkpoint.epoch + 2 == current_epoch:
        state.finalized_checkpoint = old_previous_justified_checkpoint
    # The 1st/2nd/3rd most recent epochs are justified, the 1st using the 3rd as source
    if all(bits[0:3]) and old_current_justified_checkpoint.epoch + 2 == current_epoch:
        state.finalized_checkpoint = old_current_justified_checkpoint
    # The 1st/2nd most recent epochs are justified, the 1st using the 2nd as source
    if all(bits[0:2]) and old_current_justified_checkpoint.epoch + 1 == current_epoch:
        state.finalized_checkpoint = old_current_justified_checkpoint
```

#### Inactivity scores

*[New in Altair]*

```python
def process_inactivity_updates(state: BeaconState) -> None:
    # Skip the genesis epoch as score updates are based on the previous epoch participation
    if get_current_epoch(state) == GENESIS_EPOCH:
        return

    for index in get_eligible_validator_indices(state):
        # Increase the inactivity score of inactive validators
        if index in get_unslashed_participating_indices(state, TIMELY_TARGET_FLAG_INDEX, get_previous_epoch(state)):
            state.inactivity_scores[index] -= min(1, state.inactivity_scores[index])
        else:
            state.inactivity_scores[index] += INACTIVITY_SCORE_BIAS
        # Decrease the inactivity score of all eligible validators during a leak-free epoch
        if not is_in_inactivity_leak(state):
            state.inactivity_scores[index] -= min(INACTIVITY_SCORE_RECOVERY_RATE, state.inactivity_scores[index])
```

#### Rewards and penalties

```python
def process_rewards_and_penalties(state: BeaconState) -> None:
    # No rewards are applied at the end of `GENESIS_EPOCH` because rewards are for work done in the previous epoch
    if get_current_epoch(state) == GENESIS_EPOCH:
        return

    flag_deltas = [get_flag_index_deltas(state, flag_index) for flag_index in range(len(PARTICIPATION_FLAG_WEIGHTS))]
    deltas = flag_deltas + [get_inactivity_penalty_deltas(state)]
    for (rewards, penalties) in deltas:
        for index in range(len(state.validators)):
            increase_balance(state, ValidatorIndex(index), rewards[index])
            decrease_balance(state, ValidatorIndex(index), penalties[index])
```

#### Registry updates

*[Modified in Electra:EIP7251]* — activations processed in the same loop as eligibility and ejections.

```python
def process_registry_updates(state: BeaconState) -> None:
    current_epoch = get_current_epoch(state)
    activation_epoch = compute_activation_exit_epoch(current_epoch)

    # Process activation eligibility, ejections, and activations
    for index, validator in enumerate(state.validators):
        # [Modified in Electra:EIP7251]
        if is_eligible_for_activation_queue(validator):
            validator.activation_eligibility_epoch = current_epoch + 1
        elif (
            is_active_validator(validator, current_epoch)
            and validator.effective_balance <= EJECTION_BALANCE
        ):
            # [Modified in Electra:EIP7251]
            initiate_validator_exit(state, ValidatorIndex(index))
        elif is_eligible_for_activation(state, validator):
            validator.activation_epoch = activation_epoch
```

#### Slashings

*[Modified in Electra:EIP7251]* — new algorithm for correlation penalty.

```python
def process_slashings(state: BeaconState) -> None:
    epoch = get_current_epoch(state)
    total_balance = get_total_active_balance(state)
    adjusted_total_slashing_balance = min(
        sum(state.slashings) * PROPORTIONAL_SLASHING_MULTIPLIER_BELLATRIX, total_balance
    )
    increment = EFFECTIVE_BALANCE_INCREMENT  # Factored out from total balance to avoid uint64 overflow
    penalty_per_effective_balance_increment = adjusted_total_slashing_balance // (
        total_balance // increment
    )
    for index, validator in enumerate(state.validators):
        if (
            validator.slashed
            and epoch + EPOCHS_PER_SLASHINGS_VECTOR // 2 == validator.withdrawable_epoch
        ):
            effective_balance_increments = validator.effective_balance // increment
            # [Modified in Electra:EIP7251]
            penalty = penalty_per_effective_balance_increment * effective_balance_increments
            decrease_balance(state, ValidatorIndex(index), penalty)
```

#### Eth1 data votes updates

```python
def process_eth1_data_reset(state: BeaconState) -> None:
    next_epoch = Epoch(get_current_epoch(state) + 1)
    # Reset eth1 data votes
    if next_epoch % EPOCHS_PER_ETH1_VOTING_PERIOD == 0:
        state.eth1_data_votes = []
```

#### Pending deposits processing

*[New in Electra:EIP7251]*

```python
def apply_pending_deposit(state: BeaconState, deposit: PendingDeposit) -> None:
    """
    Applies ``deposit`` to the ``state``.
    """
    validator_pubkeys = [v.pubkey for v in state.validators]
    if deposit.pubkey not in validator_pubkeys:
        # Verify the deposit signature (proof of possession) which is not checked by the deposit contract
        if is_valid_deposit_signature(
            deposit.pubkey, deposit.withdrawal_credentials, deposit.amount, deposit.signature
        ):
            add_validator_to_registry(
                state, deposit.pubkey, deposit.withdrawal_credentials, deposit.amount
            )
    else:
        validator_index = ValidatorIndex(validator_pubkeys.index(deposit.pubkey))
        increase_balance(state, validator_index, deposit.amount)
```

```python
def process_pending_deposits(state: BeaconState) -> None:
    next_epoch = Epoch(get_current_epoch(state) + 1)
    available_for_processing = state.deposit_balance_to_consume + get_activation_exit_churn_limit(
        state
    )
    processed_amount = 0
    next_deposit_index = 0
    deposits_to_postpone = []
    is_churn_limit_reached = False
    finalized_slot = compute_start_slot_at_epoch(state.finalized_checkpoint.epoch)

    for deposit in state.pending_deposits:
        # Do not process deposit requests if Eth1 bridge deposits are not yet applied.
        if (
            # Is deposit request
            deposit.slot > GENESIS_SLOT
            and
            # There are pending Eth1 bridge deposits
            state.eth1_deposit_index < state.deposit_requests_start_index
        ):
            break

        # Check if deposit has been finalized, otherwise, stop processing.
        if deposit.slot > finalized_slot:
            break

        # Check if number of processed deposits has not reached the limit, otherwise, stop processing.
        if next_deposit_index >= MAX_PENDING_DEPOSITS_PER_EPOCH:
            break

        # Read validator state
        is_validator_exited = False
        is_validator_withdrawn = False
        validator_pubkeys = [v.pubkey for v in state.validators]
        if deposit.pubkey in validator_pubkeys:
            validator = state.validators[ValidatorIndex(validator_pubkeys.index(deposit.pubkey))]
            is_validator_exited = validator.exit_epoch < FAR_FUTURE_EPOCH
            is_validator_withdrawn = validator.withdrawable_epoch < next_epoch

        if is_validator_withdrawn:
            # Deposited balance will never become active. Increase balance but do not consume churn
            apply_pending_deposit(state, deposit)
        elif is_validator_exited:
            # Validator is exiting, postpone the deposit until after withdrawable epoch
            deposits_to_postpone.append(deposit)
        else:
            # Check if deposit fits in the churn, otherwise, do no more deposit processing in this epoch.
            is_churn_limit_reached = processed_amount + deposit.amount > available_for_processing
            if is_churn_limit_reached:
                break

            # Consume churn and apply deposit.
            processed_amount += deposit.amount
            apply_pending_deposit(state, deposit)

        # Regardless of how the deposit was handled, we move on in the queue.
        next_deposit_index += 1

    state.pending_deposits = state.pending_deposits[next_deposit_index:] + deposits_to_postpone

    # Accumulate churn only if the churn limit has been hit.
    if is_churn_limit_reached:
        state.deposit_balance_to_consume = available_for_processing - processed_amount
    else:
        state.deposit_balance_to_consume = Gwei(0)
```

#### Pending consolidations processing

*[New in Electra:EIP7251]*

```python
def process_pending_consolidations(state: BeaconState) -> None:
    next_epoch = Epoch(get_current_epoch(state) + 1)
    next_pending_consolidation = 0
    for pending_consolidation in state.pending_consolidations:
        source_validator = state.validators[pending_consolidation.source_index]
        if source_validator.slashed:
            next_pending_consolidation += 1
            continue
        if source_validator.withdrawable_epoch > next_epoch:
            break

        # Calculate the consolidated balance
        source_effective_balance = min(
            state.balances[pending_consolidation.source_index], source_validator.effective_balance
        )

        # Move active balance to target. Excess balance is withdrawable.
        decrease_balance(state, pending_consolidation.source_index, source_effective_balance)
        increase_balance(state, pending_consolidation.target_index, source_effective_balance)
        next_pending_consolidation += 1

    state.pending_consolidations = state.pending_consolidations[next_pending_consolidation:]
```

#### Effective balances updates

*[Modified in Electra:EIP7251]* — uses `get_max_effective_balance`.

```python
def process_effective_balance_updates(state: BeaconState) -> None:
    # Update effective balances with hysteresis
    for index, validator in enumerate(state.validators):
        balance = state.balances[index]
        HYSTERESIS_INCREMENT = uint64(EFFECTIVE_BALANCE_INCREMENT // HYSTERESIS_QUOTIENT)
        DOWNWARD_THRESHOLD = HYSTERESIS_INCREMENT * HYSTERESIS_DOWNWARD_MULTIPLIER
        UPWARD_THRESHOLD = HYSTERESIS_INCREMENT * HYSTERESIS_UPWARD_MULTIPLIER
        # [Modified in Electra:EIP7251]
        max_effective_balance = get_max_effective_balance(validator)

        if (
            balance + DOWNWARD_THRESHOLD < validator.effective_balance
            or validator.effective_balance + UPWARD_THRESHOLD < balance
        ):
            validator.effective_balance = min(
                balance - balance % EFFECTIVE_BALANCE_INCREMENT, max_effective_balance
            )
```

#### Slashings balances updates

```python
def process_slashings_reset(state: BeaconState) -> None:
    next_epoch = Epoch(get_current_epoch(state) + 1)
    # Reset slashings
    state.slashings[next_epoch % EPOCHS_PER_SLASHINGS_VECTOR] = Gwei(0)
```

#### Randao mixes updates

```python
def process_randao_mixes_reset(state: BeaconState) -> None:
    current_epoch = get_current_epoch(state)
    next_epoch = Epoch(current_epoch + 1)
    # Set randao mix
    state.randao_mixes[next_epoch % EPOCHS_PER_HISTORICAL_VECTOR] = get_randao_mix(state, current_epoch)
```

#### Historical summaries updates

```python
def process_historical_summaries_update(state: BeaconState) -> None:
    # Set historical block root accumulator.
    next_epoch = Epoch(get_current_epoch(state) + 1)
    if next_epoch % (SLOTS_PER_HISTORICAL_ROOT // SLOTS_PER_EPOCH) == 0:
        historical_summary = HistoricalSummary(
            block_summary_root=hash_tree_root(state.block_roots),
            state_summary_root=hash_tree_root(state.state_roots),
        )
        state.historical_summaries.append(historical_summary)
```

#### Participation flags updates

```python
def process_participation_flag_updates(state: BeaconState) -> None:
    state.previous_epoch_participation = state.current_epoch_participation
    state.current_epoch_participation = [ParticipationFlags(0b0000_0000) for _ in range(len(state.validators))]
```

#### Sync committee updates

```python
def process_sync_committee_updates(state: BeaconState) -> None:
    next_epoch = get_current_epoch(state) + Epoch(1)
    if next_epoch % EPOCHS_PER_SYNC_COMMITTEE_PERIOD == 0:
        state.current_sync_committee = state.next_sync_committee
        state.next_sync_committee = get_next_sync_committee(state)
```

#### Proposer lookahead

*[New in Fulu:EIP7917]* — updates `proposer_lookahead` by shifting out the earliest epoch and appending new proposer indices for the latest epoch.

```python
def process_proposer_lookahead(state: BeaconState) -> None:
    last_epoch_start = len(state.proposer_lookahead) - SLOTS_PER_EPOCH
    # Shift out proposers in the first epoch
    state.proposer_lookahead[:last_epoch_start] = state.proposer_lookahead[SLOTS_PER_EPOCH:]
    # Fill in the last epoch with new proposer indices
    last_epoch_proposers = get_beacon_proposer_indices(
        state, Epoch(get_current_epoch(state) + MIN_SEED_LOOKAHEAD + 1)
    )
    state.proposer_lookahead[last_epoch_start:] = last_epoch_proposers
```


### Block processing

*[Modified in Electra]*

```python
def process_block(state: BeaconState, block: BeaconBlock) -> None:
    process_block_header(state, block)
    # [Modified in Electra:EIP7251]
    process_withdrawals(state, block.body.execution_payload)
    # [Modified in Electra:EIP6110]
    process_execution_payload(state, block.body, EXECUTION_ENGINE)
    process_randao(state, block.body)
    process_eth1_data(state, block.body)
    # [Modified in Electra:EIP6110:EIP7002:EIP7549:EIP7251]
    process_operations(state, block.body)
    process_sync_aggregate(state, block.body.sync_aggregate)
```

#### Block header

```python
def process_block_header(state: BeaconState, block: BeaconBlock) -> None:
    # Verify that the slots match
    assert block.slot == state.slot
    # Verify that the block is newer than latest block header
    assert block.slot > state.latest_block_header.slot
    # Verify that proposer index is the correct index
    assert block.proposer_index == get_beacon_proposer_index(state)
    # Verify that the parent matches
    assert block.parent_root == hash_tree_root(state.latest_block_header)
    # Cache current block as the new latest block
    state.latest_block_header = BeaconBlockHeader(
        slot=block.slot,
        proposer_index=block.proposer_index,
        parent_root=block.parent_root,
        state_root=Bytes32(),  # Overwritten in the next process_slot call
        body_root=hash_tree_root(block.body),
    )

    # Verify proposer is not slashed
    proposer = state.validators[block.proposer_index]
    assert not proposer.slashed
```

#### RANDAO

```python
def process_randao(state: BeaconState, body: BeaconBlockBody) -> None:
    epoch = get_current_epoch(state)
    # Verify RANDAO reveal
    proposer = state.validators[get_beacon_proposer_index(state)]
    signing_root = compute_signing_root(epoch, get_domain(state, DOMAIN_RANDAO))
    assert bls.Verify(proposer.pubkey, signing_root, body.randao_reveal)
    # Mix in RANDAO reveal
    mix = xor(get_randao_mix(state, epoch), hash(body.randao_reveal))
    state.randao_mixes[epoch % EPOCHS_PER_HISTORICAL_VECTOR] = mix
```

#### Eth1 data

```python
def process_eth1_data(state: BeaconState, body: BeaconBlockBody) -> None:
    state.eth1_data_votes.append(body.eth1_data)
    if state.eth1_data_votes.count(body.eth1_data) * 2 > EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH:
        state.eth1_data = body.eth1_data
```

#### Operations

*[Modified in Electra:EIP6110]* — disables former deposit mechanism once all prior deposits processed; adds execution request processing.

```python
def process_operations(state: BeaconState, body: BeaconBlockBody) -> None:
    # [Modified in Electra:EIP6110]
    # Disable former deposit mechanism once all prior deposits are processed
    eth1_deposit_index_limit = min(
        state.eth1_data.deposit_count, state.deposit_requests_start_index
    )
    if state.eth1_deposit_index < eth1_deposit_index_limit:
        assert len(body.deposits) == min(
            MAX_DEPOSITS, eth1_deposit_index_limit - state.eth1_deposit_index
        )
    else:
        assert len(body.deposits) == 0

    def for_ops(operations: Sequence[Any], fn: Callable[[BeaconState, Any], None]) -> None:
        for operation in operations:
            fn(state, operation)

    for_ops(body.proposer_slashings, process_proposer_slashing)
    for_ops(body.attester_slashings, process_attester_slashing)
    # [Modified in Electra:EIP7549]
    for_ops(body.attestations, process_attestation)
    for_ops(body.deposits, process_deposit)
    # [Modified in Electra:EIP7251]
    for_ops(body.voluntary_exits, process_voluntary_exit)
    for_ops(body.bls_to_execution_changes, process_bls_to_execution_change)
    # [New in Electra:EIP6110]
    for_ops(body.execution_requests.deposits, process_deposit_request)
    # [New in Electra:EIP7002:EIP7251]
    for_ops(body.execution_requests.withdrawals, process_withdrawal_request)
    # [New in Electra:EIP7251]
    for_ops(body.execution_requests.consolidations, process_consolidation_request)
```

##### Proposer slashings

```python
def process_proposer_slashing(state: BeaconState, proposer_slashing: ProposerSlashing) -> None:
    header_1 = proposer_slashing.signed_header_1.message
    header_2 = proposer_slashing.signed_header_2.message

    # Verify header slots match
    assert header_1.slot == header_2.slot
    # Verify header proposer indices match
    assert header_1.proposer_index == header_2.proposer_index
    # Verify the headers are different
    assert header_1 \!= header_2
    # Verify the proposer is slashable
    proposer = state.validators[header_1.proposer_index]
    assert is_slashable_validator(proposer, get_current_epoch(state))
    # Verify signatures
    for signed_header in (proposer_slashing.signed_header_1, proposer_slashing.signed_header_2):
        domain = get_domain(state, DOMAIN_BEACON_PROPOSER, compute_epoch_at_slot(signed_header.message.slot))
        signing_root = compute_signing_root(signed_header.message, domain)
        assert bls.Verify(proposer.pubkey, signing_root, signed_header.signature)

    slash_validator(state, header_1.proposer_index)
```

##### Attester slashings

```python
def process_attester_slashing(state: BeaconState, attester_slashing: AttesterSlashing) -> None:
    attestation_1 = attester_slashing.attestation_1
    attestation_2 = attester_slashing.attestation_2
    assert is_slashable_attestation_data(attestation_1.data, attestation_2.data)
    assert is_valid_indexed_attestation(state, attestation_1)
    assert is_valid_indexed_attestation(state, attestation_2)

    slashed_any = False
    indices = set(attestation_1.attesting_indices).intersection(attestation_2.attesting_indices)
    for index in sorted(indices):
        if is_slashable_validator(state.validators[index], get_current_epoch(state)):
            slash_validator(state, index)
            slashed_any = True
    assert slashed_any
```

##### Attestations

*[Modified in Electra:EIP7549]* — supports committee_bits for multi-committee attestations; data.index must be 0.

```python
def process_attestation(state: BeaconState, attestation: Attestation) -> None:
    data = attestation.data
    assert data.target.epoch in (get_previous_epoch(state), get_current_epoch(state))
    assert data.target.epoch == compute_epoch_at_slot(data.slot)
    assert data.slot + MIN_ATTESTATION_INCLUSION_DELAY <= state.slot

    # [Modified in Electra:EIP7549]
    assert data.index == 0
    committee_indices = get_committee_indices(attestation.committee_bits)
    committee_offset = 0
    for committee_index in committee_indices:
        assert committee_index < get_committee_count_per_slot(state, data.target.epoch)
        committee = get_beacon_committee(state, data.slot, committee_index)
        committee_attesters = set(
            attester_index
            for i, attester_index in enumerate(committee)
            if attestation.aggregation_bits[committee_offset + i]
        )
        assert len(committee_attesters) > 0
        committee_offset += len(committee)

    # Bitfield length matches total number of participants
    assert len(attestation.aggregation_bits) == committee_offset

    # Participation flag indices
    participation_flag_indices = get_attestation_participation_flag_indices(
        state, data, state.slot - data.slot
    )

    # Verify signature
    assert is_valid_indexed_attestation(state, get_indexed_attestation(state, attestation))

    # Update epoch participation flags
    if data.target.epoch == get_current_epoch(state):
        epoch_participation = state.current_epoch_participation
    else:
        epoch_participation = state.previous_epoch_participation

    proposer_reward_numerator = 0
    for index in get_attesting_indices(state, attestation):
        for flag_index, weight in enumerate(PARTICIPATION_FLAG_WEIGHTS):
            if flag_index in participation_flag_indices and not has_flag(
                epoch_participation[index], flag_index
            ):
                epoch_participation[index] = add_flag(epoch_participation[index], flag_index)
                proposer_reward_numerator += get_base_reward(state, index) * weight

    # Reward proposer
    proposer_reward_denominator = (
        (WEIGHT_DENOMINATOR - PROPOSER_WEIGHT) * WEIGHT_DENOMINATOR // PROPOSER_WEIGHT
    )
    proposer_reward = Gwei(proposer_reward_numerator // proposer_reward_denominator)
    increase_balance(state, get_beacon_proposer_index(state), proposer_reward)
```

##### Deposits

###### `is_valid_deposit_signature`

*[New in Electra:EIP7251]*

```python
def is_valid_deposit_signature(
    pubkey: BLSPubkey, withdrawal_credentials: Bytes32, amount: uint64, signature: BLSSignature
) -> bool:
    deposit_message = DepositMessage(
        pubkey=pubkey,
        withdrawal_credentials=withdrawal_credentials,
        amount=amount,
    )
    # Fork-agnostic domain since deposits are valid across forks
    domain = compute_domain(DOMAIN_DEPOSIT)
    signing_root = compute_signing_root(deposit_message, domain)
    return bls.Verify(pubkey, signing_root, signature)
```

###### `get_validator_from_deposit`

*[Modified in Electra:EIP7251]* — uses `get_max_effective_balance`.

```python
def get_validator_from_deposit(
    pubkey: BLSPubkey, withdrawal_credentials: Bytes32, amount: uint64
) -> Validator:
    validator = Validator(
        pubkey=pubkey,
        withdrawal_credentials=withdrawal_credentials,
        effective_balance=Gwei(0),
        slashed=False,
        activation_eligibility_epoch=FAR_FUTURE_EPOCH,
        activation_epoch=FAR_FUTURE_EPOCH,
        exit_epoch=FAR_FUTURE_EPOCH,
        withdrawable_epoch=FAR_FUTURE_EPOCH,
    )

    # [Modified in Electra:EIP7251]
    max_effective_balance = get_max_effective_balance(validator)
    validator.effective_balance = min(
        amount - amount % EFFECTIVE_BALANCE_INCREMENT, max_effective_balance
    )

    return validator
```

###### `add_validator_to_registry`

*[Modified in Electra:EIP7251]*

```python
def add_validator_to_registry(
    state: BeaconState, pubkey: BLSPubkey, withdrawal_credentials: Bytes32, amount: uint64
) -> None:
    index = get_index_for_new_validator(state)
    # [Modified in Electra:EIP7251]
    validator = get_validator_from_deposit(pubkey, withdrawal_credentials, amount)
    set_or_append_list(state.validators, index, validator)
    set_or_append_list(state.balances, index, amount)
    set_or_append_list(state.previous_epoch_participation, index, ParticipationFlags(0b0000_0000))
    set_or_append_list(state.current_epoch_participation, index, ParticipationFlags(0b0000_0000))
    set_or_append_list(state.inactivity_scores, index, uint64(0))
```

###### `apply_deposit`

*[Modified in Electra:EIP7251]* — queues deposit into pending_deposits.

```python
def apply_deposit(
    state: BeaconState,
    pubkey: BLSPubkey,
    withdrawal_credentials: Bytes32,
    amount: uint64,
    signature: BLSSignature,
) -> None:
    validator_pubkeys = [v.pubkey for v in state.validators]
    if pubkey not in validator_pubkeys:
        # Verify the deposit signature (proof of possession) which is not checked by the deposit contract
        if is_valid_deposit_signature(pubkey, withdrawal_credentials, amount, signature):
            # [Modified in Electra:EIP7251]
            add_validator_to_registry(state, pubkey, withdrawal_credentials, Gwei(0))
        else:
            return

    # [Modified in Electra:EIP7251]
    # Increase balance by deposit amount
    state.pending_deposits.append(
        PendingDeposit(
            pubkey=pubkey,
            withdrawal_credentials=withdrawal_credentials,
            amount=amount,
            signature=signature,
            slot=GENESIS_SLOT,  # Use GENESIS_SLOT to distinguish from a pending deposit request
        )
    )
```

###### `process_deposit`

*[Modified in Electra:EIP7251]*

```python
def process_deposit(state: BeaconState, deposit: Deposit) -> None:
    # Verify the Merkle branch
    assert is_valid_merkle_branch(
        leaf=hash_tree_root(deposit.data),
        branch=deposit.proof,
        # Add 1 for the List length mix-in
        depth=DEPOSIT_CONTRACT_TREE_DEPTH + 1,
        index=state.eth1_deposit_index,
        root=state.eth1_data.deposit_root,
    )

    # Deposits must be processed in order
    state.eth1_deposit_index += 1

    # [Modified in Electra:EIP7251]
    apply_deposit(
        state=state,
        pubkey=deposit.data.pubkey,
        withdrawal_credentials=deposit.data.withdrawal_credentials,
        amount=deposit.data.amount,
        signature=deposit.data.signature,
    )
```

##### Voluntary exits

*[Modified in Electra:EIP7251]* — checks no pending withdrawals in queue.

```python
def process_voluntary_exit(state: BeaconState, signed_voluntary_exit: SignedVoluntaryExit) -> None:
    voluntary_exit = signed_voluntary_exit.message
    validator = state.validators[voluntary_exit.validator_index]
    # Verify the validator is active
    assert is_active_validator(validator, get_current_epoch(state))
    # Verify exit has not been initiated
    assert validator.exit_epoch == FAR_FUTURE_EPOCH
    # Exits must specify an epoch when they become valid; they are not valid before then
    assert get_current_epoch(state) >= voluntary_exit.epoch
    # Verify the validator has been active long enough
    assert get_current_epoch(state) >= validator.activation_epoch + SHARD_COMMITTEE_PERIOD
    # [New in Electra:EIP7251]
    # Only exit validator if it has no pending withdrawals in the queue
    assert get_pending_balance_to_withdraw(state, voluntary_exit.validator_index) == 0
    # Verify signature
    # [Modified in Deneb:EIP7044]
    domain = compute_domain(
        DOMAIN_VOLUNTARY_EXIT, CAPELLA_FORK_VERSION, state.genesis_validators_root
    )
    signing_root = compute_signing_root(voluntary_exit, domain)
    assert bls.Verify(validator.pubkey, signing_root, signed_voluntary_exit.signature)
    # Initiate exit
    initiate_validator_exit(state, voluntary_exit.validator_index)
```

##### BLS to Execution

```python
def process_bls_to_execution_change(state: BeaconState,
                                    signed_address_change: SignedBLSToExecutionChange) -> None:
    address_change = signed_address_change.message

    assert address_change.validator_index < len(state.validators)

    validator = state.validators[address_change.validator_index]

    assert validator.withdrawal_credentials[:1] == BLS_WITHDRAWAL_PREFIX
    assert validator.withdrawal_credentials[1:] == hash(address_change.from_bls_pubkey)[1:]

    # Fork-agnostic domain since address changes are valid across forks
    domain = compute_domain(DOMAIN_BLS_TO_EXECUTION_CHANGE, genesis_validators_root=state.genesis_validators_root)
    signing_root = compute_signing_root(address_change, domain)
    assert bls.Verify(address_change.from_bls_pubkey, signing_root, signed_address_change.signature)

    validator.withdrawal_credentials = (
        ETH1_ADDRESS_WITHDRAWAL_PREFIX
        + b'\x00' * 11
        + address_change.to_execution_address
    )
```

##### Execution layer withdrawal requests

*[New in Electra:EIP7002:EIP7251]*

```python
def process_withdrawal_request(state: BeaconState, withdrawal_request: WithdrawalRequest) -> None:
    amount = withdrawal_request.amount
    is_full_exit_request = amount == FULL_EXIT_REQUEST_AMOUNT

    # If partial withdrawal queue is full, only full exits are processed
    if (
        len(state.pending_partial_withdrawals) == PENDING_PARTIAL_WITHDRAWALS_LIMIT
        and not is_full_exit_request
    ):
        return

    validator_pubkeys = [v.pubkey for v in state.validators]
    # Verify pubkey exists
    request_pubkey = withdrawal_request.validator_pubkey
    if request_pubkey not in validator_pubkeys:
        return
    index = ValidatorIndex(validator_pubkeys.index(request_pubkey))
    validator = state.validators[index]

    # Verify withdrawal credentials
    has_correct_credential = has_execution_withdrawal_credential(validator)
    is_correct_source_address = (
        validator.withdrawal_credentials[12:] == withdrawal_request.source_address
    )
    if not (has_correct_credential and is_correct_source_address):
        return
    # Verify the validator is active
    if not is_active_validator(validator, get_current_epoch(state)):
        return
    # Verify exit has not been initiated
    if validator.exit_epoch \!= FAR_FUTURE_EPOCH:
        return
    # Verify the validator has been active long enough
    if get_current_epoch(state) < validator.activation_epoch + SHARD_COMMITTEE_PERIOD:
        return

    pending_balance_to_withdraw = get_pending_balance_to_withdraw(state, index)

    if is_full_exit_request:
        # Only exit validator if it has no pending withdrawals in the queue
        if pending_balance_to_withdraw == 0:
            initiate_validator_exit(state, index)
        return

    has_sufficient_effective_balance = validator.effective_balance >= MIN_ACTIVATION_BALANCE
    has_excess_balance = (
        state.balances[index] > MIN_ACTIVATION_BALANCE + pending_balance_to_withdraw
    )

    # Only allow partial withdrawals with compounding withdrawal credentials
    if (
        has_compounding_withdrawal_credential(validator)
        and has_sufficient_effective_balance
        and has_excess_balance
    ):
        to_withdraw = min(
            state.balances[index] - MIN_ACTIVATION_BALANCE - pending_balance_to_withdraw, amount
        )
        exit_queue_epoch = compute_exit_epoch_and_update_churn(state, to_withdraw)
        withdrawable_epoch = Epoch(exit_queue_epoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY)
        state.pending_partial_withdrawals.append(
            PendingPartialWithdrawal(
                validator_index=index,
                amount=to_withdraw,
                withdrawable_epoch=withdrawable_epoch,
            )
        )
```

##### Deposit requests

*[New in Electra:EIP6110]*

```python
def process_deposit_request(state: BeaconState, deposit_request: DepositRequest) -> None:
    # Set deposit request start index
    if state.deposit_requests_start_index == UNSET_DEPOSIT_REQUESTS_START_INDEX:
        state.deposit_requests_start_index = deposit_request.index

    # Create pending deposit
    state.pending_deposits.append(
        PendingDeposit(
            pubkey=deposit_request.pubkey,
            withdrawal_credentials=deposit_request.withdrawal_credentials,
            amount=deposit_request.amount,
            signature=deposit_request.signature,
            slot=state.slot,
        )
    )
```

##### Execution layer consolidation requests

*[New in Electra:EIP7251]*

###### `is_valid_switch_to_compounding_request`

```python
def is_valid_switch_to_compounding_request(
    state: BeaconState, consolidation_request: ConsolidationRequest
) -> bool:
    # Switch to compounding requires source and target be equal
    if consolidation_request.source_pubkey \!= consolidation_request.target_pubkey:
        return False

    # Verify pubkey exists
    source_pubkey = consolidation_request.source_pubkey
    validator_pubkeys = [v.pubkey for v in state.validators]
    if source_pubkey not in validator_pubkeys:
        return False

    source_validator = state.validators[ValidatorIndex(validator_pubkeys.index(source_pubkey))]

    # Verify request has been authorized
    if source_validator.withdrawal_credentials[12:] \!= consolidation_request.source_address:
        return False

    # Verify source withdrawal credentials
    if not has_eth1_withdrawal_credential(source_validator):
        return False

    # Verify the source is active
    current_epoch = get_current_epoch(state)
    if not is_active_validator(source_validator, current_epoch):
        return False

    # Verify exit for source has not been initiated
    if source_validator.exit_epoch \!= FAR_FUTURE_EPOCH:
        return False

    return True
```

###### `process_consolidation_request`

```python
def process_consolidation_request(
    state: BeaconState, consolidation_request: ConsolidationRequest
) -> None:
    if is_valid_switch_to_compounding_request(state, consolidation_request):
        validator_pubkeys = [v.pubkey for v in state.validators]
        request_source_pubkey = consolidation_request.source_pubkey
        source_index = ValidatorIndex(validator_pubkeys.index(request_source_pubkey))
        switch_to_compounding_validator(state, source_index)
        return

    # Verify that source \!= target, so a consolidation cannot be used as an exit
    if consolidation_request.source_pubkey == consolidation_request.target_pubkey:
        return
    # If the pending consolidations queue is full, consolidation requests are ignored
    if len(state.pending_consolidations) == PENDING_CONSOLIDATIONS_LIMIT:
        return
    # If there is too little available consolidation churn limit, consolidation requests are ignored
    if get_consolidation_churn_limit(state) <= MIN_ACTIVATION_BALANCE:
        return

    validator_pubkeys = [v.pubkey for v in state.validators]
    # Verify pubkeys exists
    request_source_pubkey = consolidation_request.source_pubkey
    request_target_pubkey = consolidation_request.target_pubkey
    if request_source_pubkey not in validator_pubkeys:
        return
    if request_target_pubkey not in validator_pubkeys:
        return
    source_index = ValidatorIndex(validator_pubkeys.index(request_source_pubkey))
    target_index = ValidatorIndex(validator_pubkeys.index(request_target_pubkey))
    source_validator = state.validators[source_index]
    target_validator = state.validators[target_index]

    # Verify source withdrawal credentials
    has_correct_credential = has_execution_withdrawal_credential(source_validator)
    is_correct_source_address = (
        source_validator.withdrawal_credentials[12:] == consolidation_request.source_address
    )
    if not (has_correct_credential and is_correct_source_address):
        return

    # Verify that target has compounding withdrawal credentials
    if not has_compounding_withdrawal_credential(target_validator):
        return

    # Verify the source and the target are active
    current_epoch = get_current_epoch(state)
    if not is_active_validator(source_validator, current_epoch):
        return
    if not is_active_validator(target_validator, current_epoch):
        return
    # Verify exits for source and target have not been initiated
    if source_validator.exit_epoch \!= FAR_FUTURE_EPOCH:
        return
    if target_validator.exit_epoch \!= FAR_FUTURE_EPOCH:
        return
    # Verify the source has been active long enough
    if current_epoch < source_validator.activation_epoch + SHARD_COMMITTEE_PERIOD:
        return
    # Verify the source has no pending withdrawals in the queue
    if get_pending_balance_to_withdraw(state, source_index) > 0:
        return

    # Initiate source validator exit and append pending consolidation
    source_validator.exit_epoch = compute_consolidation_epoch_and_update_churn(
        state, source_validator.effective_balance
    )
    source_validator.withdrawable_epoch = Epoch(
        source_validator.exit_epoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY
    )
    state.pending_consolidations.append(
        PendingConsolidation(source_index=source_index, target_index=target_index)
    )
```

#### Sync aggregate processing

```python
def process_sync_aggregate(state: BeaconState, sync_aggregate: SyncAggregate) -> None:
    # Verify sync committee aggregate signature signing over the previous slot block root
    committee_pubkeys = state.current_sync_committee.pubkeys
    participant_pubkeys = [pubkey for pubkey, bit in zip(committee_pubkeys, sync_aggregate.sync_committee_bits) if bit]
    previous_slot = max(state.slot, Slot(1)) - Slot(1)
    domain = get_domain(state, DOMAIN_SYNC_COMMITTEE, compute_epoch_at_slot(previous_slot))
    signing_root = compute_signing_root(get_block_root_at_slot(state, previous_slot), domain)
    assert eth_fast_aggregate_verify(participant_pubkeys, signing_root, sync_aggregate.sync_committee_signature)

    # Compute participant and proposer rewards
    total_active_increments = get_total_active_balance(state) // EFFECTIVE_BALANCE_INCREMENT
    total_base_rewards = Gwei(get_base_reward_per_increment(state) * total_active_increments)
    max_participant_rewards = Gwei(total_base_rewards * SYNC_REWARD_WEIGHT // WEIGHT_DENOMINATOR // SLOTS_PER_EPOCH)
    participant_reward = Gwei(max_participant_rewards // SYNC_COMMITTEE_SIZE)
    proposer_reward = Gwei(participant_reward * PROPOSER_WEIGHT // (WEIGHT_DENOMINATOR - PROPOSER_WEIGHT))

    # Apply participant and proposer rewards
    all_pubkeys = [v.pubkey for v in state.validators]
    committee_indices = [ValidatorIndex(all_pubkeys.index(pubkey)) for pubkey in state.current_sync_committee.pubkeys]
    for participant_index, participation_bit in zip(committee_indices, sync_aggregate.sync_committee_bits):
        if participation_bit:
            increase_balance(state, participant_index, participant_reward)
            increase_balance(state, get_beacon_proposer_index(state), proposer_reward)
        else:
            decrease_balance(state, participant_index, participant_reward)
```

#### Execution payload

##### `get_expected_withdrawals`

*[Modified in Electra:EIP7251]* — processes pending partial withdrawals before sweep.

```python
def get_expected_withdrawals(state: BeaconState) -> Tuple[Sequence[Withdrawal], uint64]:
    epoch = get_current_epoch(state)
    withdrawal_index = state.next_withdrawal_index
    validator_index = state.next_withdrawal_validator_index
    withdrawals: List[Withdrawal] = []
    processed_partial_withdrawals_count = 0

    # [New in Electra:EIP7251]
    # Consume pending partial withdrawals
    for withdrawal in state.pending_partial_withdrawals:
        if (
            withdrawal.withdrawable_epoch > epoch
            or len(withdrawals) == MAX_PENDING_PARTIALS_PER_WITHDRAWALS_SWEEP
        ):
            break

        validator = state.validators[withdrawal.validator_index]
        has_sufficient_effective_balance = validator.effective_balance >= MIN_ACTIVATION_BALANCE
        total_withdrawn = sum(
            w.amount for w in withdrawals if w.validator_index == withdrawal.validator_index
        )
        balance = state.balances[withdrawal.validator_index] - total_withdrawn
        has_excess_balance = balance > MIN_ACTIVATION_BALANCE
        if (
            validator.exit_epoch == FAR_FUTURE_EPOCH
            and has_sufficient_effective_balance
            and has_excess_balance
        ):
            withdrawable_balance = min(balance - MIN_ACTIVATION_BALANCE, withdrawal.amount)
            withdrawals.append(
                Withdrawal(
                    index=withdrawal_index,
                    validator_index=withdrawal.validator_index,
                    address=ExecutionAddress(validator.withdrawal_credentials[12:]),
                    amount=withdrawable_balance,
                )
            )
            withdrawal_index += WithdrawalIndex(1)

        processed_partial_withdrawals_count += 1

    # Sweep for remaining.
    bound = min(len(state.validators), MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP)
    for _ in range(bound):
        validator = state.validators[validator_index]
        # [Modified in Electra:EIP7251]
        total_withdrawn = sum(w.amount for w in withdrawals if w.validator_index == validator_index)
        balance = state.balances[validator_index] - total_withdrawn
        if is_fully_withdrawable_validator(validator, balance, epoch):
            withdrawals.append(
                Withdrawal(
                    index=withdrawal_index,
                    validator_index=validator_index,
                    address=ExecutionAddress(validator.withdrawal_credentials[12:]),
                    amount=balance,
                )
            )
            withdrawal_index += WithdrawalIndex(1)
        elif is_partially_withdrawable_validator(validator, balance):
            withdrawals.append(
                Withdrawal(
                    index=withdrawal_index,
                    validator_index=validator_index,
                    address=ExecutionAddress(validator.withdrawal_credentials[12:]),
                    # [Modified in Electra:EIP7251]
                    amount=balance - get_max_effective_balance(validator),
                )
            )
            withdrawal_index += WithdrawalIndex(1)
        if len(withdrawals) == MAX_WITHDRAWALS_PER_PAYLOAD:
            break
        validator_index = ValidatorIndex((validator_index + 1) % len(state.validators))
    return withdrawals, processed_partial_withdrawals_count
```

##### `process_withdrawals`

*[Modified in Electra:EIP7251]* — updates pending partial withdrawals queue.

```python
def process_withdrawals(state: BeaconState, payload: ExecutionPayload) -> None:
    # [Modified in Electra:EIP7251]
    expected_withdrawals, processed_partial_withdrawals_count = get_expected_withdrawals(state)

    assert payload.withdrawals == expected_withdrawals

    for withdrawal in expected_withdrawals:
        decrease_balance(state, withdrawal.validator_index, withdrawal.amount)

    # [New in Electra:EIP7251]
    # Update pending partial withdrawals
    state.pending_partial_withdrawals = state.pending_partial_withdrawals[
        processed_partial_withdrawals_count:
    ]

    # Update the next withdrawal index if this block contained withdrawals
    if len(expected_withdrawals) \!= 0:
        latest_withdrawal = expected_withdrawals[-1]
        state.next_withdrawal_index = WithdrawalIndex(latest_withdrawal.index + 1)

    # Update the next validator index to start the next withdrawal sweep
    if len(expected_withdrawals) == MAX_WITHDRAWALS_PER_PAYLOAD:
        # Next sweep starts after the latest withdrawal's validator index
        next_validator_index = ValidatorIndex(
            (expected_withdrawals[-1].validator_index + 1) % len(state.validators)
        )
        state.next_withdrawal_validator_index = next_validator_index
    else:
        # Advance sweep by the max length of the sweep if there was not a full set of withdrawals
        next_index = state.next_withdrawal_validator_index + MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP
        next_validator_index = ValidatorIndex(next_index % len(state.validators))
        state.next_withdrawal_validator_index = next_validator_index
```

##### `get_execution_requests_list`

*[New in Electra:EIP7685]* — encodes execution requests.

```python
def get_execution_requests_list(execution_requests: ExecutionRequests) -> Sequence[bytes]:
    requests = [
        (DEPOSIT_REQUEST_TYPE, execution_requests.deposits),
        (WITHDRAWAL_REQUEST_TYPE, execution_requests.withdrawals),
        (CONSOLIDATION_REQUEST_TYPE, execution_requests.consolidations),
    ]

    return [
        request_type + ssz_serialize(request_data)
        for request_type, request_data in requests
        if len(request_data) \!= 0
    ]
```

##### `process_execution_payload`

*[Modified in Fulu:EIP7892]* — blob limit determined by `get_blob_parameters`.

```python
def process_execution_payload(
    state: BeaconState, body: BeaconBlockBody, execution_engine: ExecutionEngine
) -> None:
    payload = body.execution_payload

    # Verify consistency of the parent hash with respect to the previous execution payload header
    assert payload.parent_hash == state.latest_execution_payload_header.block_hash
    # Verify prev_randao
    assert payload.prev_randao == get_randao_mix(state, get_current_epoch(state))
    # Verify timestamp
    assert payload.timestamp == compute_time_at_slot(state, state.slot)
    # [Modified in Fulu:EIP7892]
    # Verify commitments are under limit
    assert (
        len(body.blob_kzg_commitments)
        <= get_blob_parameters(get_current_epoch(state)).max_blobs_per_block
    )

    # Compute list of versioned hashes
    versioned_hashes = [
        kzg_commitment_to_versioned_hash(commitment) for commitment in body.blob_kzg_commitments
    ]

    # Verify the execution payload is valid
    assert execution_engine.verify_and_notify_new_payload(
        NewPayloadRequest(
            execution_payload=payload,
            versioned_hashes=versioned_hashes,
            parent_beacon_block_root=state.latest_block_header.parent_root,
            # [New in Electra]
            execution_requests=body.execution_requests,
        )
    )

    # Cache execution payload header
    state.latest_execution_payload_header = ExecutionPayloadHeader(
        parent_hash=payload.parent_hash,
        fee_recipient=payload.fee_recipient,
        state_root=payload.state_root,
        receipts_root=payload.receipts_root,
        logs_bloom=payload.logs_bloom,
        prev_randao=payload.prev_randao,
        block_number=payload.block_number,
        gas_limit=payload.gas_limit,
        gas_used=payload.gas_used,
        timestamp=payload.timestamp,
        extra_data=payload.extra_data,
        base_fee_per_gas=payload.base_fee_per_gas,
        block_hash=payload.block_hash,
        transactions_root=hash_tree_root(payload.transactions),
        withdrawals_root=hash_tree_root(payload.withdrawals),
        blob_gas_used=payload.blob_gas_used,
        excess_blob_gas=payload.excess_blob_gas,
    )
```

### Execution engine

#### Request data

##### `NewPayloadRequest`

*[Modified in Electra]* — `execution_requests` field added.

```python
@dataclass
class NewPayloadRequest(object):
    execution_payload: ExecutionPayload
    versioned_hashes: Sequence[VersionedHash]
    parent_beacon_block_root: Root
    # [New in Electra]
    execution_requests: ExecutionRequests
```

#### Engine APIs

The implementation-dependent `ExecutionEngine` protocol encapsulates the execution sub-system logic via:

* a state object `self.execution_state` of type `ExecutionState`
* a notification function `self.notify_new_payload` which may apply changes to the `self.execution_state`

The body of these functions are implementation dependent. The Engine API may be used to implement this and similarly defined functions via an external execution engine.

##### `notify_new_payload`

*[Modified in Electra]* — includes `execution_requests_list`.

```python
def notify_new_payload(
    self: ExecutionEngine,
    execution_payload: ExecutionPayload,
    parent_beacon_block_root: Root,
    execution_requests_list: Sequence[bytes],
) -> bool:
    """
    Return ``True`` if and only if ``execution_payload`` and ``execution_requests_list``
    are valid with respect to ``self.execution_state``.
    """
    ...
```

##### `is_valid_block_hash`

*[Modified in Electra]* — includes `execution_requests_list`.

```python
def is_valid_block_hash(
    self: ExecutionEngine,
    execution_payload: ExecutionPayload,
    parent_beacon_block_root: Root,
    execution_requests_list: Sequence[bytes],
) -> bool:
    """
    Return ``True`` if and only if ``execution_payload.block_hash`` is computed correctly.
    """
    ...
```

##### `is_valid_versioned_hashes`

```python
def is_valid_versioned_hashes(self: ExecutionEngine, new_payload_request: NewPayloadRequest) -> bool:
    """
    Return ``True`` if and only if the version hashes computed by the blob transactions of
    ``new_payload_request.execution_payload`` matches ``new_payload_request.version_hashes``.
    """
    ...
```

##### `verify_and_notify_new_payload`

*[Modified in Electra]* — passes `execution_requests_list` to `is_valid_block_hash` and `notify_new_payload`.

```python
def verify_and_notify_new_payload(
    self: ExecutionEngine, new_payload_request: NewPayloadRequest
) -> bool:
    """
    Return ``True`` if and only if ``new_payload_request`` is valid with respect to ``self.execution_state``.
    """
    execution_payload = new_payload_request.execution_payload
    parent_beacon_block_root = new_payload_request.parent_beacon_block_root
    # [New in Electra]
    execution_requests_list = get_execution_requests_list(new_payload_request.execution_requests)

    if b"" in execution_payload.transactions:
        return False

    # [Modified in Electra]
    if not self.is_valid_block_hash(
        execution_payload, parent_beacon_block_root, execution_requests_list
    ):
        return False

    if not self.is_valid_versioned_hashes(new_payload_request):
        return False

    # [Modified in Electra]
    if not self.notify_new_payload(
        execution_payload, parent_beacon_block_root, execution_requests_list
    ):
        return False

    return True
```
