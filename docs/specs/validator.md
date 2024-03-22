# Honest Validator

This is an accompanying document to [The Beacon Chain](./beacon-chain.md), which describes the expected actions of a "validator" participating in the Ethereum proof-of-stake protocol.

## Table of contents

<!-- TOC -->
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Constants](#constants)
  - [Misc](#misc)
- [Containers](#containers)
  - [`Eth1Block`](#eth1block)
  - [`AggregateAndProof`](#aggregateandproof)
  - [`SignedAggregateAndProof`](#signedaggregateandproof)
- [Becoming a validator](#becoming-a-validator)
  - [Initialization](#initialization)
    - [BLS public key](#bls-public-key)
    - [Withdrawal credentials](#withdrawal-credentials)
      - [`BLS_WITHDRAWAL_PREFIX`](#bls_withdrawal_prefix)
      - [`ETH1_ADDRESS_WITHDRAWAL_PREFIX`](#eth1_address_withdrawal_prefix)
  - [Submit deposit](#submit-deposit)
  - [Process deposit](#process-deposit)
  - [Validator index](#validator-index)
  - [Activation](#activation)
- [Validator assignments](#validator-assignments)
  - [Lookahead](#lookahead)
- [Beacon chain responsibilities](#beacon-chain-responsibilities)
  - [Block proposal](#block-proposal)
    - [Preparing for a `BeaconBlock`](#preparing-for-a-beaconblock)
      - [Slot](#slot)
      - [Proposer index](#proposer-index)
      - [Parent root](#parent-root)
    - [Constructing the `BeaconBlockBody`](#constructing-the-beaconblockbody)
      - [Randao reveal](#randao-reveal)
      - [Eth1 Data](#eth1-data)
        - [`get_eth1_data`](#get_eth1_data)
      - [Proposer slashings](#proposer-slashings)
      - [Attester slashings](#attester-slashings)
      - [Attestations](#attestations)
      - [Deposits](#deposits)
      - [Voluntary exits](#voluntary-exits)
    - [Packaging into a `SignedBeaconBlock`](#packaging-into-a-signedbeaconblock)
      - [State root](#state-root)
      - [Signature](#signature)
  - [Attesting](#attesting)
    - [Attestation data](#attestation-data)
      - [General](#general)
      - [LMD GHOST vote](#lmd-ghost-vote)
      - [FFG vote](#ffg-vote)
    - [Construct attestation](#construct-attestation)
      - [Data](#data)
      - [Aggregation bits](#aggregation-bits)
      - [Aggregate signature](#aggregate-signature)
    - [Broadcast attestation](#broadcast-attestation)
  - [Attestation aggregation](#attestation-aggregation)
    - [Aggregation selection](#aggregation-selection)
    - [Construct aggregate](#construct-aggregate)
      - [Data](#data-1)
      - [Aggregation bits](#aggregation-bits-1)
      - [Aggregate signature](#aggregate-signature-1)
    - [Broadcast aggregate](#broadcast-aggregate)
- [How to avoid slashing](#how-to-avoid-slashing)
  - [Proposer slashing](#proposer-slashing)
  - [Attester slashing](#attester-slashing)
- [Protection best practices](#protection-best-practices)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->
<!-- /TOC -->

## Introduction

This document represents the expected behavior of an "honest validator" of the Ethereum proof-of-stake protocol. This document does not distinguish between a "node" (i.e. the functionality of following and reading the beacon chain) and a "validator client" (i.e. the functionality of actively participating in consensus). The separation of concerns between these (potentially) two pieces of software is left as a design decision that is out of scope.

A validator is an entity that participates in the consensus of the Ethereum proof-of-stake protocol. This is an optional role for users in which they can post ETH as collateral and verify and attest to the validity of blocks to seek financial returns in exchange for building and securing the protocol. This is similar to execution networks in which miners provide collateral in the form of hardware/hash-power to seek returns in exchange for building and securing the protocol.

Altair introduces a new type of committee: the sync committee. Sync committees are responsible for signing each block of the canonical chain and there exists an efficient algorithm for light clients to sync the chain using the output of the sync committees.
See the [sync protocol](./light-client/sync-protocol.md) for further details on the light client sync.
Under this network upgrade, validators track their participation in this new committee type and produce the relevant signatures as required.
Block proposers incorporate the (aggregated) sync committee signatures into each block they produce.

## Prerequisites

All terminology, constants, functions, and protocol mechanics defined in the [The Beacon Chain](./beacon-chain.md) and [Deposit Contract](./deposit-contract.md) doc are requisite for this document and used throughout.

## Constants

### Misc

| Name | Value | Unit | Duration |
| - | - | :-: | :-: |
| `TARGET_AGGREGATORS_PER_COMMITTEE` | `2**4` (= 16) | validators |
| `TARGET_AGGREGATORS_PER_SYNC_SUBCOMMITTEE` | `2**4` (= 16) | validators |
| `SYNC_COMMITTEE_SUBNET_COUNT` | `4` | The number of sync committee subnets used in the gossipsub aggregation protocol. |

## Containers

### `Eth1Block`

```python
class Eth1Block(Container):
    timestamp: uint64
    deposit_root: Root
    deposit_count: uint64
    # All other eth1 block fields
```

### `AggregateAndProof`

```python
class AggregateAndProof(Container):
    aggregator_index: ValidatorIndex
    aggregate: Attestation
    selection_proof: BLSSignature
```

### `SignedAggregateAndProof`

```python
class SignedAggregateAndProof(Container):
    message: AggregateAndProof
    signature: BLSSignature
```

### `SyncCommitteeMessage`

```python
class SyncCommitteeMessage(Container):
    # Slot to which this contribution pertains
    slot: Slot
    # Block root for this signature
    beacon_block_root: Root
    # Index of the validator that produced this signature
    validator_index: ValidatorIndex
    # Signature by the validator over the block root of `slot`
    signature: BLSSignature
```

### `SyncCommitteeContribution`

```python
class SyncCommitteeContribution(Container):
    # Slot to which this contribution pertains
    slot: Slot
    # Block root for this contribution
    beacon_block_root: Root
    # The subcommittee this contribution pertains to out of the broader sync committee
    subcommittee_index: uint64
    # A bit is set if a signature from the validator at the corresponding
    # index in the subcommittee is present in the aggregate `signature`.
    aggregation_bits: Bitvector[SYNC_COMMITTEE_SIZE // SYNC_COMMITTEE_SUBNET_COUNT]
    # Signature by the validator(s) over the block root of `slot`
    signature: BLSSignature
```

### `ContributionAndProof`

```python
class ContributionAndProof(Container):
    aggregator_index: ValidatorIndex
    contribution: SyncCommitteeContribution
    selection_proof: BLSSignature
```

### `SignedContributionAndProof`

```python
class SignedContributionAndProof(Container):
    message: ContributionAndProof
    signature: BLSSignature
```

### `SyncAggregatorSelectionData`

```python
class SyncAggregatorSelectionData(Container):
    slot: Slot
    subcommittee_index: uint64
```

### `BlobsBundle`

*[New in Deneb:EIP4844]*

```python
@dataclass
class BlobsBundle(object):
    commitments: Sequence[KZGCommitment]
    proofs: Sequence[KZGProof]
    blobs: Sequence[Blob]
```

### `GetPayloadResponse`

```python
@dataclass
class GetPayloadResponse(object):
    execution_payload: ExecutionPayload
    block_value: uint256
    blobs_bundle: BlobsBundle  # [New in Deneb:EIP4844]
```

## Helpers

### `get_pow_block_at_terminal_total_difficulty`

```python
def get_pow_block_at_terminal_total_difficulty(pow_chain: Dict[Hash32, PowBlock]) -> Optional[PowBlock]:
    # `pow_chain` abstractly represents all blocks in the PoW chain
    for block in pow_chain.values():
        block_reached_ttd = block.total_difficulty >= TERMINAL_TOTAL_DIFFICULTY
        if block_reached_ttd:
            # If genesis block, no parent exists so reaching TTD alone qualifies as valid terminal block
            if block.parent_hash == Hash32():
                return block
            parent = pow_chain[block.parent_hash]
            parent_reached_ttd = parent.total_difficulty >= TERMINAL_TOTAL_DIFFICULTY
            if not parent_reached_ttd:
                return block

    return None
```

### `get_terminal_pow_block`

```python
def get_terminal_pow_block(pow_chain: Dict[Hash32, PowBlock]) -> Optional[PowBlock]:
    if TERMINAL_BLOCK_HASH != Hash32():
        # Terminal block hash override takes precedence over terminal total difficulty
        if TERMINAL_BLOCK_HASH in pow_chain:
            return pow_chain[TERMINAL_BLOCK_HASH]
        else:
            return None

    return get_pow_block_at_terminal_total_difficulty(pow_chain)
```

*Note*: This function does *not* use simple serialize `hash_tree_root` as to
avoid requiring simple serialize hashing capabilities in the Execution Layer.

## Protocols (new in Bellatrix)

### `ExecutionEngine`

*Note*: `get_payload` function is added to the `ExecutionEngine` protocol for use as a validator.

The body of this function is implementation dependent.
The Engine API may be used to implement it with an external execution engine.

#### `get_payload`

Given the `payload_id`, `get_payload` returns `GetPayloadResponse` with the most recent version of
the execution payload that has been built since the corresponding call to `notify_forkchoice_updated` method.

```python
def get_payload(self: ExecutionEngine, payload_id: PayloadId) -> GetPayloadResponse:
    """
    Return ExecutionPayload, uint256, BlobsBundle objects.
    """
    ...
```

## Becoming a validator

### Initialization

A validator must initialize many parameters locally before submitting a deposit and joining the validator registry.

#### BLS public key

Validator public keys are [G1 points](beacon-chain.md#bls-signatures) on the [BLS12-381 curve](https://z.cash/blog/new-snark-curve). A private key, `privkey`, must be securely generated along with the resultant `pubkey`. This `privkey` must be "hot", that is, constantly available to sign data throughout the lifetime of the validator.

#### Withdrawal credentials

The `withdrawal_credentials` field constrains validator withdrawals.
The first byte of this 32-byte field is a withdrawal prefix which defines the semantics of the remaining 31 bytes.

The following withdrawal prefixes are currently supported.

##### `BLS_WITHDRAWAL_PREFIX`

Withdrawal credentials with the BLS withdrawal prefix allow a BLS key pair
`(bls_withdrawal_privkey, bls_withdrawal_pubkey)` to trigger withdrawals.
The `withdrawal_credentials` field must be such that:

- `withdrawal_credentials[:1] == BLS_WITHDRAWAL_PREFIX`
- `withdrawal_credentials[1:] == hash(bls_withdrawal_pubkey)[1:]`

*Note*: The `bls_withdrawal_privkey` is not required for validating and can be kept in cold storage.

##### `ETH1_ADDRESS_WITHDRAWAL_PREFIX`

Withdrawal credentials with the Eth1 address withdrawal prefix specify
a 20-byte Eth1 address `eth1_withdrawal_address` as the recipient for all withdrawals.
The `eth1_withdrawal_address` can be the address of either an externally owned account or of a contract.

The `withdrawal_credentials` field must be such that:

- `withdrawal_credentials[:1] == ETH1_ADDRESS_WITHDRAWAL_PREFIX`
- `withdrawal_credentials[1:12] == b'\x00' * 11`
- `withdrawal_credentials[12:] == eth1_withdrawal_address`

After the merge of the current Ethereum execution layer into the Beacon Chain,
withdrawals to `eth1_withdrawal_address` will simply be increases to the account's ETH balance that do **NOT** trigger any EVM execution.

### Submit deposit

Deposits are made to the [deposit contract](./deposit-contract.md) located at `DEPOSIT_CONTRACT_ADDRESS`.

To submit a deposit:

- Pack the validator's [initialization parameters](#initialization) into `deposit_data`, a [`DepositData`](./beacon-chain.md#depositdata) SSZ object.
- Let `amount` be the amount in Gwei to be deposited by the validator where `amount >= MIN_DEPOSIT_AMOUNT`.
- Set `deposit_data.pubkey` to validator's `pubkey`.
- Set `deposit_data.withdrawal_credentials` to `withdrawal_credentials`.
- Set `deposit_data.amount` to `amount`.
- Let `deposit_message` be a `DepositMessage` with all the `DepositData` contents except the `signature`.
- Let `signature` be the result of `bls.Sign` of the `compute_signing_root(deposit_message, domain)` with `domain=compute_domain(DOMAIN_DEPOSIT)`. (*Warning*: Deposits *must* be signed with `GENESIS_FORK_VERSION`, calling `compute_domain` without a second argument defaults to the correct version).
- Let `deposit_data_root` be `hash_tree_root(deposit_data)`.
- Send a transaction on the Ethereum execution chain to `DEPOSIT_CONTRACT_ADDRESS` executing `def deposit(pubkey: bytes[48], withdrawal_credentials: bytes[32], signature: bytes[96], deposit_data_root: bytes32)` along with a deposit of `amount` Gwei.

*Note*: Deposits made for the same `pubkey` are treated as for the same validator. A singular `Validator` will be added to `state.validators` with each additional deposit amount added to the validator's balance. A validator can only be activated when total deposits for the validator pubkey meet or exceed `MAX_EFFECTIVE_BALANCE`.

### Process deposit

Deposits cannot be processed into the beacon chain until the execution block in which they were deposited or any of its descendants is added to the beacon chain `state.eth1_data`. This takes *a minimum* of `ETH1_FOLLOW_DISTANCE` Eth1 blocks (~8 hours) plus `EPOCHS_PER_ETH1_VOTING_PERIOD` epochs (~6.8 hours). Once the requisite execution block data is added, the deposit will normally be added to a beacon chain block and processed into the `state.validators` within an epoch or two. The validator is then in a queue to be activated.

### Validator index

Once a validator has been processed and added to the beacon state's `validators`, the validator's `validator_index` is defined by the index into the registry at which the [`ValidatorRecord`](./beacon-chain.md#validator) contains the `pubkey` specified in the validator's deposit. A validator's `validator_index` is guaranteed to not change from the time of initial deposit until the validator exits and fully withdraws. This `validator_index` is used throughout the specification to dictate validator roles and responsibilities at any point and should be stored locally.

### Activation

In normal operation, the validator is quickly activated, at which point the validator is added to the shuffling and begins validation after an additional `MAX_SEED_LOOKAHEAD` epochs (25.6 minutes).

The function [`is_active_validator`](./beacon-chain.md#is_active_validator) can be used to check if a validator is active during a given epoch. Usage is as follows:

```python
def check_if_validator_active(state: BeaconState, validator_index: ValidatorIndex) -> bool:
    validator = state.validators[validator_index]
    return is_active_validator(validator, get_current_epoch(state))
```

Once a validator is activated, the validator is assigned [responsibilities](#beacon-chain-responsibilities) until exited.

*Note*: There is a maximum validator churn per finalized epoch, so the delay until activation is variable depending upon finality, total active validator balance, and the number of validators in the queue to be activated.

## Validator assignments

A validator can get committee assignments for a given epoch using the following helper via `get_committee_assignment(state, epoch, validator_index)` where `epoch <= next_epoch`.

```python
def get_committee_assignment(state: BeaconState,
                             epoch: Epoch,
                             validator_index: ValidatorIndex
                             ) -> Optional[Tuple[Sequence[ValidatorIndex], CommitteeIndex, Slot]]:
    """
    Return the committee assignment in the ``epoch`` for ``validator_index``.
    ``assignment`` returned is a tuple of the following form:
        * ``assignment[0]`` is the list of validators in the committee
        * ``assignment[1]`` is the index to which the committee is assigned
        * ``assignment[2]`` is the slot at which the committee is assigned
    Return None if no assignment.
    """
    next_epoch = Epoch(get_current_epoch(state) + 1)
    assert epoch <= next_epoch

    start_slot = compute_start_slot_at_epoch(epoch)
    committee_count_per_slot = get_committee_count_per_slot(state, epoch)
    for slot in range(start_slot, start_slot + SLOTS_PER_EPOCH):
        for index in range(committee_count_per_slot):
            committee = get_beacon_committee(state, Slot(slot), CommitteeIndex(index))
            if validator_index in committee:
                return committee, CommitteeIndex(index), Slot(slot)
    return None
```

A validator can use the following function to see if they are supposed to propose during a slot. This function can only be run with a `state` of the slot in question. Proposer selection is only stable within the context of the current epoch.

```python
def is_proposer(state: BeaconState, validator_index: ValidatorIndex) -> bool:
    return get_beacon_proposer_index(state) == validator_index
```

*Note*: To see if a validator is assigned to propose during the slot, the beacon state must be in the epoch in question. At the epoch boundaries, the validator must run an epoch transition into the epoch to successfully check the proposal assignment of the first slot.

*Note*: `BeaconBlock` proposal is distinct from beacon committee assignment, and in a given epoch each responsibility might occur at a different slot.

### Sync Committee (new in Altair)

To determine sync committee assignments, a validator can run the following function: `is_assigned_to_sync_committee(state, epoch, validator_index)` where `epoch` is an epoch number within the current or next sync committee period.
This function is a predicate indicating the presence or absence of the validator in the corresponding sync committee for the queried sync committee period.

*Note*: Being assigned to a sync committee for a given `slot` means that the validator produces and broadcasts signatures for `slot - 1` for inclusion in `slot`.
This means that when assigned to an `epoch` sync committee signatures must be produced and broadcast for slots on range `[compute_start_slot_at_epoch(epoch) - 1, compute_start_slot_at_epoch(epoch) + SLOTS_PER_EPOCH - 1)`
rather than for the range `[compute_start_slot_at_epoch(epoch), compute_start_slot_at_epoch(epoch) + SLOTS_PER_EPOCH)`.
To reduce complexity during the Altair fork, sync committees are not expected to produce signatures for `compute_start_slot_at_epoch(ALTAIR_FORK_EPOCH) - 1`.

```python
def compute_sync_committee_period(epoch: Epoch) -> uint64:
    return epoch // EPOCHS_PER_SYNC_COMMITTEE_PERIOD
```

```python
def is_assigned_to_sync_committee(state: BeaconState,
                                  epoch: Epoch,
                                  validator_index: ValidatorIndex) -> bool:
    sync_committee_period = compute_sync_committee_period(epoch)
    current_epoch = get_current_epoch(state)
    current_sync_committee_period = compute_sync_committee_period(current_epoch)
    next_sync_committee_period = current_sync_committee_period + 1
    assert sync_committee_period in (current_sync_committee_period, next_sync_committee_period)

    pubkey = state.validators[validator_index].pubkey
    if sync_committee_period == current_sync_committee_period:
        return pubkey in state.current_sync_committee.pubkeys
    else:  # sync_committee_period == next_sync_committee_period
        return pubkey in state.next_sync_committee.pubkeys
```

### Lookahead

The beacon chain shufflings are designed to provide a minimum of 1 epoch lookahead
on the validator's upcoming committee assignments for attesting dictated by the shuffling and slot.
Note that this lookahead does not apply to proposing, which must be checked during the epoch in question.

`get_committee_assignment` should be called at the start of each epoch
to get the assignment for the next epoch (`current_epoch + 1`).
A validator should plan for future assignments by noting their assigned attestation
slot and joining the committee index attestation subnet related to their committee assignment.

Specifically a validator should:

- Call `_, committee_index, _ = get_committee_assignment(state, next_epoch, validator_index)` when checking for next epoch assignments.
- Calculate the committees per slot for the next epoch: `committees_per_slot = get_committee_count_per_slot(state, next_epoch)`
- Calculate the subnet index: `subnet_id = compute_subnet_for_attestation(committees_per_slot, slot, committee_index)`
- Find peers of the pubsub topic `beacon_attestation_{subnet_id}`.
  - If an *insufficient* number of current peers are subscribed to the topic, the validator must discover new peers on this topic. Via the discovery protocol, find peers with an ENR containing the `attnets` entry such that `ENR["attnets"][subnet_id] == True`. Then validate that the peers are still persisted on the desired topic by requesting `GetMetaData` and checking the resulting `attnets` field.
  - If the validator is assigned to be an aggregator for the slot (see `is_aggregator()`), then subscribe to the topic.

*Note*: If the validator is *not* assigned to be an aggregator, the validator only needs sufficient number of peers on the topic to be able to publish messages. The validator does not need to *subscribe* and listen to all messages on the topic.

#### Sync Committee

The sync committee shufflings give validators 1 sync committee period of lookahead which amounts to `EPOCHS_PER_SYNC_COMMITTEE_PERIOD` epochs.
At any given `epoch`, the `BeaconState` contains the current `SyncCommittee` and the next `SyncCommittee`.
Once every `EPOCHS_PER_SYNC_COMMITTEE_PERIOD` epochs, the next `SyncCommittee` becomes the current `SyncCommittee` and the next committee is computed and stored.

*Note*: The data required to compute a given committee is not cached in the `BeaconState` after committees are calculated at the period boundaries.
For this reason, *always* get committee assignments via the fields of the `BeaconState` (`current_sync_committee` and `next_sync_committee`) or use the above reference code.

A validator should plan for future sync committee assignments by noting which sync committee periods they are selected for participation.
Specifically, a validator should:

- Upon (re)syncing the chain and upon sync committee period boundaries, check for assignments in the current and next sync committee periods.
- If the validator is in the current sync committee period, then they perform the responsibilities below for sync committee rewards.
- If the validator is in the next sync committee period, they should wait until the next `EPOCHS_PER_SYNC_COMMITTEE_PERIOD` boundary and then perform the responsibilities throughout that period.

## Beacon chain responsibilities

A validator has two primary responsibilities to the beacon chain: [proposing blocks](#block-proposal) and [creating attestations](#attesting). Proposals happen infrequently, whereas attestations should be created once per epoch.

*Note*: A validator must not propose on or attest to a block that isn't deemed valid, i.e. hasn't yet passed the beacon chain state transition and execution validations. In future upgrades, an "execution Proof-of-Custody" will be integrated to prevent outsourcing of execution payload validations.

### Block and sidecar proposal

A validator is expected to propose a [`SignedBeaconBlock`](./beacon-chain.md#signedbeaconblock) at
the beginning of any `slot` during which `is_proposer(state, validator_index)` returns `True`.

To propose, the validator selects a `BeaconBlock`, `parent` using this process:

1. Compute fork choice's view of the head at the start of `slot`, after running
   `on_tick` and applying any queued attestations from `slot - 1`.
   Set `head_root = get_head(store)`.
2. Compute the _proposer head_, which is the head upon which the proposer SHOULD build in order to
   incentivise timely block propagation by other validators.
   Set `parent_root = get_proposer_head(store, head_root, slot)`.
   A proposer may set `parent_root == head_root` if proposer re-orgs are not implemented or have
   been disabled.
3. Let `parent` be the block with `parent_root`.

The validator creates, signs, and broadcasts a `block` that is a child of `parent`
and satisfies a valid [beacon chain state transition](./beacon-chain.md#beacon-chain-state-transition-function).
Note that the parent's slot must be strictly less than the slot of the block about to be proposed,
i.e. `parent.slot < slot`.

There is one proposer per slot, so if there are N active validators any individual validator
will on average be assigned to propose once per N slots (e.g. at 312,500 validators = 10 million ETH, that's once per ~6 weeks).

*Note*: In this section, `state` is the state of the slot for the block proposal *without* the block yet applied.
That is, `state` is the `previous_state` processed through any empty slots up to the assigned slot using `process_slots(previous_state, slot)`.

#### Preparing for a `BeaconBlock`

To construct a `BeaconBlockBody`, a `block` (`BeaconBlock`) is defined with the necessary context for a block proposal:

##### Slot

Set `block.slot = slot` where `slot` is the current slot at which the validator has been selected to propose. The `parent` selected must satisfy that `parent.slot < block.slot`.

*Note*: There might be "skipped" slots between the `parent` and `block`. These skipped slots are processed in the state transition function without per-block processing.

##### Proposer index

Set `block.proposer_index = validator_index` where `validator_index` is the validator chosen to propose at this slot. The private key mapping to `state.validators[validator_index].pubkey` is used to sign the block.

##### Parent root

Set `block.parent_root = hash_tree_root(parent)`.

#### Constructing the `BeaconBlockBody`

##### Randao reveal

Set `block.body.randao_reveal = epoch_signature` where `epoch_signature` is obtained from:

```python
def get_epoch_signature(state: BeaconState, block: BeaconBlock, privkey: int) -> BLSSignature:
    domain = get_domain(state, DOMAIN_RANDAO, compute_epoch_at_slot(block.slot))
    signing_root = compute_signing_root(compute_epoch_at_slot(block.slot), domain)
    return bls.Sign(privkey, signing_root)
```

##### Eth1 Data

The `block.body.eth1_data` field is for block proposers to vote on recent Eth1 data.
This recent data contains an Eth1 block hash as well as the associated deposit root
(as calculated by the `get_deposit_root()` method of the deposit contract) and
deposit count after execution of the corresponding Eth1 block.
If over half of the block proposers in the current Eth1 voting period vote for the same
`eth1_data` then `state.eth1_data` updates immediately allowing new deposits to be processed.
Each deposit in `block.body.deposits` must verify against `state.eth1_data.eth1_deposit_root`.

###### `get_eth1_data`

Let `Eth1Block` be an abstract object representing Eth1 blocks with the `timestamp` and deposit contract data available.

Let `get_eth1_data(block: Eth1Block) -> Eth1Data` be the function that returns the Eth1 data for a given Eth1 block.

An honest block proposer sets `block.body.eth1_data = get_eth1_vote(state, eth1_chain)` where:

```python
def compute_time_at_slot(state: BeaconState, slot: Slot) -> uint64:
    return uint64(state.genesis_time + slot * SECONDS_PER_SLOT)
```

```python
def voting_period_start_time(state: BeaconState) -> uint64:
    eth1_voting_period_start_slot = Slot(state.slot - state.slot % (EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH))
    return compute_time_at_slot(state, eth1_voting_period_start_slot)
```

```python
def is_candidate_block(block: Eth1Block, period_start: uint64) -> bool:
    return (
        block.timestamp + SECONDS_PER_ETH1_BLOCK * ETH1_FOLLOW_DISTANCE <= period_start
        and block.timestamp + SECONDS_PER_ETH1_BLOCK * ETH1_FOLLOW_DISTANCE * 2 >= period_start
    )
```

```python
def get_eth1_vote(state: BeaconState, eth1_chain: Sequence[Eth1Block]) -> Eth1Data:
    period_start = voting_period_start_time(state)
    # `eth1_chain` abstractly represents all blocks in the eth1 chain sorted by ascending block height
    votes_to_consider = [
        get_eth1_data(block) for block in eth1_chain
        if (
            is_candidate_block(block, period_start)
            # Ensure cannot move back to earlier deposit contract states
            and get_eth1_data(block).deposit_count >= state.eth1_data.deposit_count
        )
    ]

    # Valid votes already cast during this period
    valid_votes = [vote for vote in state.eth1_data_votes if vote in votes_to_consider]

    # Default vote on latest eth1 block data in the period range unless eth1 chain is not live
    # Non-substantive casting for linter
    state_eth1_data: Eth1Data = state.eth1_data
    default_vote = votes_to_consider[len(votes_to_consider) - 1] if any(votes_to_consider) else state_eth1_data

    return max(
        valid_votes,
        key=lambda v: (valid_votes.count(v), -valid_votes.index(v)),  # Tiebreak by smallest distance
        default=default_vote
    )
```

##### Proposer slashings

Up to `MAX_PROPOSER_SLASHINGS`, [`ProposerSlashing`](./beacon-chain.md#proposerslashing) objects can be included in the `block`. The proposer slashings must satisfy the verification conditions found in [proposer slashings processing](./beacon-chain.md#proposer-slashings). The validator receives a small "whistleblower" reward for each proposer slashing found and included.

##### Attester slashings

Up to `MAX_ATTESTER_SLASHINGS`, [`AttesterSlashing`](./beacon-chain.md#attesterslashing) objects can be included in the `block`. The attester slashings must satisfy the verification conditions found in [attester slashings processing](./beacon-chain.md#attester-slashings). The validator receives a small "whistleblower" reward for each attester slashing found and included.

##### Attestations

Up to `MAX_ATTESTATIONS`, aggregate attestations can be included in the `block`. The attestations added must satisfy the verification conditions found in [attestation processing](./beacon-chain.md#attestations). To maximize profit, the validator should attempt to gather aggregate attestations that include singular attestations from the largest number of validators whose signatures from the same epoch have not previously been added on chain.

##### Deposits

If there are any unprocessed deposits for the existing `state.eth1_data` (i.e. `state.eth1_data.deposit_count > state.eth1_deposit_index`), then pending deposits *must* be added to the block. The expected number of deposits is exactly `min(MAX_DEPOSITS, eth1_data.deposit_count - state.eth1_deposit_index)`.  These [`deposits`](./beacon-chain.md#deposit) are constructed from the `Deposit` logs from the [deposit contract](./deposit-contract.md) and must be processed in sequential order. The deposits included in the `block` must satisfy the verification conditions found in [deposits processing](./beacon-chain.md#deposits).

The `proof` for each deposit must be constructed against the deposit root contained in `state.eth1_data` rather than the deposit root at the time the deposit was initially logged from the execution chain. This entails storing a full deposit merkle tree locally and computing updated proofs against the `eth1_data.deposit_root` as needed. See [`minimal_merkle.py`](https://github.com/ethereum/research/blob/master/spec_pythonizer/utils/merkle_minimal.py) for a sample implementation.

##### Voluntary exits

Up to `MAX_VOLUNTARY_EXITS`, [`VoluntaryExit`](./beacon-chain.md#voluntaryexit) objects can be included in the `block`. The exits must satisfy the verification conditions found in [exits processing](./beacon-chain.md#voluntary-exits).

*Note*: If a slashing for a validator is included in the same block as a
voluntary exit, the voluntary exit will fail and cause the block to be invalid
due to the slashing being processed first. Implementers must take heed of this
operation interaction when packing blocks.

##### Sync committee

The proposer receives a number of `SyncCommitteeContribution`s (wrapped in `SignedContributionAndProof`s on the wire) from validators in the sync committee who are selected to partially aggregate signatures from independent subcommittees formed by breaking the full sync committee into `SYNC_COMMITTEE_SUBNET_COUNT` pieces (see below for details).

The proposer collects the contributions that match their local view of the chain (i.e. `contribution.beacon_block_root == block.parent_root`) for further aggregation when preparing a block.
Of these contributions, proposers should select the best contribution seen across all aggregators for each subnet/subcommittee.
A contribution with more valid signatures is better than a contribution with fewer signatures.

Recall `block.body.sync_aggregate.sync_committee_bits` is a `Bitvector` where the `i`th bit is `True` if the corresponding validator in the sync committee has produced a valid signature,
and that `block.body.sync_aggregate.sync_committee_signature` is the aggregate BLS signature combining all of the valid signatures.

Given a collection of the best seen `contributions` (with no repeating `subcommittee_index` values) and the `BeaconBlock` under construction,
the proposer processes them as follows:

```python
def process_sync_committee_contributions(block: BeaconBlock,
                                         contributions: Set[SyncCommitteeContribution]) -> None:
    sync_aggregate = SyncAggregate()
    signatures = []
    sync_subcommittee_size = SYNC_COMMITTEE_SIZE // SYNC_COMMITTEE_SUBNET_COUNT

    for contribution in contributions:
        subcommittee_index = contribution.subcommittee_index
        for index, participated in enumerate(contribution.aggregation_bits):
            if participated:
                participant_index = sync_subcommittee_size * subcommittee_index + index
                sync_aggregate.sync_committee_bits[participant_index] = True
        signatures.append(contribution.signature)

    sync_aggregate.sync_committee_signature = bls.Aggregate(signatures)

    block.body.sync_aggregate = sync_aggregate
```

*Note*: The resulting block must pass the validations for the `SyncAggregate` defined in `process_sync_aggregate` defined in the [state transition document](./beacon-chain.md#sync-aggregate-processing).
In particular, this means `SyncCommitteeContribution`s received from gossip must have a `beacon_block_root` that matches the proposer's local view of the chain.

##### ExecutionPayload

To obtain an execution payload, a block proposer building a block on top of a `state` must take the following actions:

1. Set `payload_id = prepare_execution_payload(state, pow_chain, safe_block_hash, finalized_block_hash, suggested_fee_recipient, execution_engine)`, where:

    - `state` is the state object after applying `process_slots(state, slot)` transition to the resulting state of the parent blockprocessingdictionary key
    - `safe_block_hash` is the return value of the `get_safe_execution_payload_hash(store: Store)` function call
    - `finalized_block_hash` is the hash of the latest finalized execution payload (`Hash32()` if none yet finalized)
    - `suggested_fee_recipient` is the value suggested to be used for the `fee_recipient` field of the execution payload

```python
def prepare_execution_payload(state: BeaconState,
                              safe_block_hash: Hash32,
                              finalized_block_hash: Hash32,
                              suggested_fee_recipient: ExecutionAddress,
                              execution_engine: ExecutionEngine) -> Optional[PayloadId]:
    # Verify consistency of the parent hash with respect to the previous execution payload header
    parent_hash = state.latest_execution_payload_header.block_hash

    # Set the forkchoice head and initiate the payload build process
    payload_attributes = PayloadAttributes(
        timestamp=compute_timestamp_at_slot(state, state.slot),
        prev_randao=get_randao_mix(state, get_current_epoch(state)),
        suggested_fee_recipient=suggested_fee_recipient,
        withdrawals=get_expected_withdrawals(state),
        parent_beacon_block_root=hash_tree_root(state.latest_block_header),  # [New in Deneb:EIP4788]
    )
    return execution_engine.notify_forkchoice_updated(
        head_block_hash=parent_hash,
        safe_block_hash=safe_block_hash,
        finalized_block_hash=finalized_block_hash,
        payload_attributes=payload_attributes,
    )
```

2. Set `block.body.execution_payload = get_execution_payload(payload_id, execution_engine)`, where:

```python
def get_execution_payload(payload_id: Optional[PayloadId], execution_engine: ExecutionEngine) -> ExecutionPayload:
    if payload_id is None:
        # Pre-merge, empty payload
        return ExecutionPayload()
    else:
        return execution_engine.get_payload(payload_id).execution_payload
```

*Note*: It is recommended for a validator to call `prepare_execution_payload` as soon as input parameters become known,
and make subsequent calls to this function when any of these parameters gets updated.

##### Blob KZG commitments

*[New in Deneb:EIP4844]*

1. The execution payload is obtained from the execution engine as defined above using `payload_id`. The response also includes a `blobs_bundle` entry containing the corresponding `blobs`, `commitments`, and `proofs`.
2. Set `block.body.blob_kzg_commitments = commitments`.

##### BLS to execution changes

Up to `MAX_BLS_TO_EXECUTION_CHANGES`, [`BLSToExecutionChange`](./beacon-chain.md#blstoexecutionchange) objects can be included in the `block`. The BLS to execution changes must satisfy the verification conditions found in [BLS to execution change processing](./beacon-chain.md#new-process_bls_to_execution_change).

#### Constructing the `BlobSidecar`s

*[New in Deneb:EIP4844]*

To construct a `BlobSidecar`, a `blob_sidecar` is defined with the necessary context for block and sidecar proposal.

##### Sidecar

Blobs associated with a block are packaged into sidecar objects for distribution to the associated sidecar topic, the `blob_sidecar_{subnet_id}` pubsub topic.

Each `sidecar` is obtained from:
```python
def get_blob_sidecars(signed_block: SignedBeaconBlock,
                      blobs: Sequence[Blob],
                      blob_kzg_proofs: Sequence[KZGProof]) -> Sequence[BlobSidecar]:
    block = signed_block.message
    block_header = BeaconBlockHeader(
        slot=block.slot,
        proposer_index=block.proposer_index,
        parent_root=block.parent_root,
        state_root=block.state_root,
        body_root=hash_tree_root(block.body),
    )
    signed_block_header = SignedBeaconBlockHeader(message=block_header, signature=signed_block.signature)
    return [
        BlobSidecar(
            index=index,
            blob=blob,
            kzg_commitment=block.body.blob_kzg_commitments[index],
            kzg_proof=blob_kzg_proofs[index],
            signed_block_header=signed_block_header,
            kzg_commitment_inclusion_proof=compute_merkle_proof(
                block.body,
                get_generalized_index(BeaconBlockBody, 'blob_kzg_commitments', index),
            ),
        )
        for index, blob in enumerate(blobs)
    ]
```

The `subnet_id` for the `blob_sidecar` is calculated with:
- Let `blob_index = blob_sidecar.index`.
- Let `subnet_id = compute_subnet_for_blob_sidecar(blob_index)`.

```python
def compute_subnet_for_blob_sidecar(blob_index: BlobIndex) -> SubnetID:
    return SubnetID(blob_index % BLOB_SIDECAR_SUBNET_COUNT)
```

After publishing the peers on the network may request the sidecar through sync-requests, or a local user may be interested.

The validator MUST hold on to sidecars for `MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS` epochs and serve when capable,
to ensure the data-availability of these blobs throughout the network.

After `MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS` nodes MAY prune the sidecars and/or stop serving them.

### Changing from BLS to execution withdrawal credentials

First, the validator must construct a valid [`BLSToExecutionChange`](./beacon-chain.md#blstoexecutionchange) `message`.
This `message` contains the `validator_index` for the validator who wishes to change their credentials, the `from_bls_pubkey` -- the BLS public key corresponding to the **withdrawal BLS secret key** used to form the `BLS_WITHDRAWAL_PREFIX` withdrawal credential, and the `to_execution_address` specifying the execution layer address to which the validator's balances will be withdrawn.

*Note*: The withdrawal key pair used to construct the `BLS_WITHDRAWAL_PREFIX` withdrawal credential should be distinct from the signing key pair used to operate the validator under typical circumstances. Consult your validator deposit tooling documentation for further details if you are not aware of the difference.

*Warning*: This message can only be included on-chain once and is
irreversible so ensure the correctness and accessibility to `to_execution_address`.

Next, the validator signs the assembled `message: BLSToExecutionChange` with the **withdrawal BLS secret key** and this
`signature` is placed into a `SignedBLSToExecutionChange` message along with the inner `BLSToExecutionChange` `message`.
Note that the `SignedBLSToExecutionChange` message should pass all of the validations in [`process_bls_to_execution_change`](./beacon-chain.md#new-process_bls_to_execution_change).

The `SignedBLSToExecutionChange` message should then be submitted to the consensus layer network. Once included on-chain,
the withdrawal credential change takes effect. No further action is required for a validator to enter into the automated
withdrawal process.

*Note*: A node *should* prioritize locally received `BLSToExecutionChange` operations to ensure these changes make it on-chain
through self published blocks even if the rest of the network censors.

#### Packaging into a `SignedBeaconBlock`

##### State root

Set `block.state_root = hash_tree_root(state)` of the resulting `state` of the `parent -> block` state transition.

*Note*: To calculate `state_root`, the validator should first run the state transition function on an unsigned `block` containing a stub for the `state_root`.
It is useful to be able to run a state transition function (working on a copy of the state) that does *not* validate signatures or state root for this purpose:

```python
def compute_new_state_root(state: BeaconState, block: BeaconBlock) -> Root:
    temp_state: BeaconState = state.copy()
    signed_block = SignedBeaconBlock(message=block)
    state_transition(temp_state, signed_block, validate_result=False)
    return hash_tree_root(temp_state)
```

##### Signature

`signed_block = SignedBeaconBlock(message=block, signature=block_signature)`, where `block_signature` is obtained from:

```python
def get_block_signature(state: BeaconState, block: BeaconBlock, privkey: int) -> BLSSignature:
    domain = get_domain(state, DOMAIN_BEACON_PROPOSER, compute_epoch_at_slot(block.slot))
    signing_root = compute_signing_root(block, domain)
    return bls.Sign(privkey, signing_root)
```

### Attesting

A validator is expected to create, sign, and broadcast an attestation during each epoch. The `committee`, assigned `index`, and assigned `slot` for which the validator performs this role during an epoch are defined by `get_committee_assignment(state, epoch, validator_index)`.

A validator should create and broadcast the `attestation` to the associated attestation subnet when either (a) the validator has received a valid block from the expected block proposer for the assigned `slot` or (b) `1 / INTERVALS_PER_SLOT` of the `slot` has transpired (`SECONDS_PER_SLOT / INTERVALS_PER_SLOT` seconds after the start of `slot`) -- whichever comes *first*.

*Note*: Although attestations during `GENESIS_EPOCH` do not count toward FFG finality, these initial attestations do give weight to the fork choice, are rewarded, and should be made.

#### Attestation data

First, the validator should construct `attestation_data`, an [`AttestationData`](./beacon-chain.md#attestationdata) object based upon the state at the assigned slot.

- Let `head_block` be the result of running the fork choice during the assigned slot.
- Let `head_state` be the state of `head_block` processed through any empty slots up to the assigned slot using `process_slots(state, slot)`.

##### General

- Set `attestation_data.slot = slot` where `slot` is the assigned slot.
- Set `attestation_data.index = index` where `index` is the index associated with the validator's committee.

##### LMD GHOST vote

Set `attestation_data.beacon_block_root = hash_tree_root(head_block)`.

##### FFG vote

- Set `attestation_data.source = head_state.current_justified_checkpoint`.
- Set `attestation_data.target = Checkpoint(epoch=get_current_epoch(head_state), root=epoch_boundary_block_root)` where `epoch_boundary_block_root` is the root of block at the most recent epoch boundary.

*Note*: `epoch_boundary_block_root` can be looked up in the state using:

- Let `start_slot = compute_start_slot_at_epoch(get_current_epoch(head_state))`.
- Let `epoch_boundary_block_root = hash_tree_root(head_block) if start_slot == head_state.slot else get_block_root(state, get_current_epoch(head_state))`.

#### Construct attestation

Next, the validator creates `attestation`, an [`Attestation`](./beacon-chain.md#attestation) object.

##### Data

Set `attestation.data = attestation_data` where `attestation_data` is the `AttestationData` object defined in the previous section, [attestation data](#attestation-data).

##### Aggregation bits

- Let `attestation.aggregation_bits` be a `Bitlist[MAX_VALIDATORS_PER_COMMITTEE]` of length `len(committee)`, where the bit of the index of the validator in the `committee` is set to `0b1`.

*Note*: Calling `get_attesting_indices(state, attestation.data, attestation.aggregation_bits)` should return a list of length equal to 1, containing `validator_index`.

##### Aggregate signature

Set `attestation.signature = attestation_signature` where `attestation_signature` is obtained from:

```python
def get_attestation_signature(state: BeaconState, attestation_data: AttestationData, privkey: int) -> BLSSignature:
    domain = get_domain(state, DOMAIN_BEACON_ATTESTER, attestation_data.target.epoch)
    signing_root = compute_signing_root(attestation_data, domain)
    return bls.Sign(privkey, signing_root)
```

#### Broadcast attestation

Finally, the validator broadcasts `attestation` to the associated attestation subnet, the `beacon_attestation_{subnet_id}` pubsub topic.

The `subnet_id` for the `attestation` is calculated with:

- Let `committees_per_slot = get_committee_count_per_slot(state, attestation.data.target.epoch)`.
- Let `subnet_id = compute_subnet_for_attestation(committees_per_slot, attestation.data.slot, attestation.data.index)`.

```python
def compute_subnet_for_attestation(committees_per_slot: uint64,
                                   slot: Slot,
                                   committee_index: CommitteeIndex) -> SubnetID:
    """
    Compute the correct subnet for an attestation for Phase 0.
    Note, this mimics expected future behavior where attestations will be mapped to their shard subnet.
    """
    slots_since_epoch_start = uint64(slot % SLOTS_PER_EPOCH)
    committees_since_epoch_start = committees_per_slot * slots_since_epoch_start

    return SubnetID((committees_since_epoch_start + committee_index) % ATTESTATION_SUBNET_COUNT)
```

### Attestation aggregation

Some validators are selected to locally aggregate attestations with a similar `attestation_data` to their constructed `attestation` for the assigned `slot`.

#### Aggregation selection

A validator is selected to aggregate based upon the return value of `is_aggregator()`.

```python
def get_slot_signature(state: BeaconState, slot: Slot, privkey: int) -> BLSSignature:
    domain = get_domain(state, DOMAIN_SELECTION_PROOF, compute_epoch_at_slot(slot))
    signing_root = compute_signing_root(slot, domain)
    return bls.Sign(privkey, signing_root)
```

```python
def is_aggregator(state: BeaconState, slot: Slot, index: CommitteeIndex, slot_signature: BLSSignature) -> bool:
    committee = get_beacon_committee(state, slot, index)
    modulo = max(1, len(committee) // TARGET_AGGREGATORS_PER_COMMITTEE)
    return bytes_to_uint64(hash(slot_signature)[0:8]) % modulo == 0
```

#### Construct aggregate

If the validator is selected to aggregate (`is_aggregator()`), they construct an aggregate attestation via the following.

Collect `attestations` seen via gossip during the `slot` that have an equivalent `attestation_data` to that constructed by the validator. If `len(attestations) > 0`, create an `aggregate_attestation: Attestation` with the following fields.

##### Data

Set `aggregate_attestation.data = attestation_data` where `attestation_data` is the `AttestationData` object that is the same for each individual attestation being aggregated.

##### Aggregation bits

Let `aggregate_attestation.aggregation_bits` be a `Bitlist[MAX_VALIDATORS_PER_COMMITTEE]` of length `len(committee)`, where each bit set from each individual attestation is set to `0b1`.

##### Aggregate signature

Set `aggregate_attestation.signature = aggregate_signature` where `aggregate_signature` is obtained from:

```python
def get_aggregate_signature(attestations: Sequence[Attestation]) -> BLSSignature:
    signatures = [attestation.signature for attestation in attestations]
    return bls.Aggregate(signatures)
```

#### Broadcast aggregate

If the validator is selected to aggregate (`is_aggregator`), then they broadcast their best aggregate as a `SignedAggregateAndProof` to the global aggregate channel (`beacon_aggregate_and_proof`) `2 / INTERVALS_PER_SLOT` of the way through the `slot`-that is, `SECONDS_PER_SLOT * 2 / INTERVALS_PER_SLOT` seconds after the start of `slot`.

Selection proofs are provided in `AggregateAndProof` to prove to the gossip channel that the validator has been selected as an aggregator.

`AggregateAndProof` messages are signed by the aggregator and broadcast inside of `SignedAggregateAndProof` objects to prevent a class of DoS attacks and message forgeries.

First, `aggregate_and_proof = get_aggregate_and_proof(state, validator_index, aggregate_attestation, privkey)` is constructed.

```python
def get_aggregate_and_proof(state: BeaconState,
                            aggregator_index: ValidatorIndex,
                            aggregate: Attestation,
                            privkey: int) -> AggregateAndProof:
    return AggregateAndProof(
        aggregator_index=aggregator_index,
        aggregate=aggregate,
        selection_proof=get_slot_signature(state, aggregate.data.slot, privkey),
    )
```

Then `signed_aggregate_and_proof = SignedAggregateAndProof(message=aggregate_and_proof, signature=signature)` is constructed and broadcast. Where `signature` is obtained from:

```python
def get_aggregate_and_proof_signature(state: BeaconState,
                                      aggregate_and_proof: AggregateAndProof,
                                      privkey: int) -> BLSSignature:
    aggregate = aggregate_and_proof.aggregate
    domain = get_domain(state, DOMAIN_AGGREGATE_AND_PROOF, compute_epoch_at_slot(aggregate.data.slot))
    signing_root = compute_signing_root(aggregate_and_proof, domain)
    return bls.Sign(privkey, signing_root)
```

### Sync committees (new in Altair)

Sync committee members employ an aggregation scheme to reduce load on the global proposer channel that is monitored by all potential proposers to be able to include the full output of the sync committee every slot.
Sync committee members produce individual signatures on subnets (similar to the attestation subnets) via `SyncCommitteeMessage`s which are then collected by aggregators sampled from the sync subcommittees to produce a `SyncCommitteeContribution` which is gossiped to proposers.
This process occurs each slot.

#### Sync committee messages

##### Prepare sync committee message

If a validator is in the current sync committee (i.e. `is_assigned_to_sync_committee()` above returns `True`), then for every `slot` in the current sync committee period, the validator should prepare a `SyncCommitteeMessage` for the previous slot (`slot - 1`) according to the logic in `get_sync_committee_message` as soon as they have determined the head block of `slot - 1`. This means that when assigned to `slot` a `SyncCommitteeMessage` is prepared and broadcast in `slot - 1` instead of `slot`.

This logic is triggered upon the same conditions as when producing an attestation.
Meaning, a sync committee member should produce and broadcast a `SyncCommitteeMessage` either when (a) the validator has received a valid block from the expected block proposer for the current `slot` or (b) one-third of the slot has transpired (`SECONDS_PER_SLOT / INTERVALS_PER_SLOT` seconds after the start of the slot) -- whichever comes first.

`get_sync_committee_message(state, block_root, validator_index, privkey)` assumes the parameter `state` is the head state corresponding to processing the block up to the current slot as determined by the fork choice (including any empty slots up to the current slot processed with `process_slots` on top of the latest block), `block_root` is the root of the head block, `validator_index` is the index of the validator in the registry `state.validators` controlled by `privkey`, and `privkey` is the BLS private key for the validator.

```python
def get_sync_committee_message(state: BeaconState,
                               block_root: Root,
                               validator_index: ValidatorIndex,
                               privkey: int) -> SyncCommitteeMessage:
    epoch = get_current_epoch(state)
    domain = get_domain(state, DOMAIN_SYNC_COMMITTEE, epoch)
    signing_root = compute_signing_root(block_root, domain)
    signature = bls.Sign(privkey, signing_root)

    return SyncCommitteeMessage(
        slot=state.slot,
        beacon_block_root=block_root,
        validator_index=validator_index,
        signature=signature,
    )
```

##### Broadcast sync committee message

The validator broadcasts the assembled signature to the assigned subnet, the `sync_committee_{subnet_id}` pubsub topic.

The `subnet_id` is derived from the position in the sync committee such that the sync committee is divided into "subcommittees".
`subnet_id` can be computed via `compute_subnets_for_sync_committee(state, validator_index)` where `state` is a `BeaconState` during the matching sync committee period.

*Note*: This function returns multiple deduplicated subnets if a given validator index is included multiple times in a given sync committee across multiple subcommittees.

```python
def compute_subnets_for_sync_committee(state: BeaconState, validator_index: ValidatorIndex) -> Set[uint64]:
    next_slot_epoch = compute_epoch_at_slot(Slot(state.slot + 1))
    if compute_sync_committee_period(get_current_epoch(state)) == compute_sync_committee_period(next_slot_epoch):
        sync_committee = state.current_sync_committee
    else:
        sync_committee = state.next_sync_committee

    target_pubkey = state.validators[validator_index].pubkey
    sync_committee_indices = [index for index, pubkey in enumerate(sync_committee.pubkeys) if pubkey == target_pubkey]
    return set([
        uint64(index // (SYNC_COMMITTEE_SIZE // SYNC_COMMITTEE_SUBNET_COUNT))
        for index in sync_committee_indices
    ])
```

*Note*: Subnet assignment does not change during the duration of a validator's assignment to a given sync committee.

*Note*: If a validator has multiple `subnet_id` results from `compute_subnets_for_sync_committee`, the validator should broadcast a copy of the `sync_committee_message` on each of the distinct subnets.

#### Sync committee contributions

Each slot, some sync committee members in each subcommittee are selected to aggregate the `SyncCommitteeMessage`s into a `SyncCommitteeContribution` which is broadcast on a global channel for inclusion into the next block.

##### Aggregation selection

A validator is selected to aggregate based on the value returned by `is_sync_committee_aggregator()` where `signature` is the BLS signature returned by `get_sync_committee_selection_proof()`.
The signature function takes a `BeaconState` with the relevant sync committees for the queried `slot` (i.e. `state.slot` is within the span covered by the current or next sync committee period), the `subcommittee_index` equal to the `subnet_id`, and the `privkey` is the BLS private key associated with the validator.

```python
def get_sync_committee_selection_proof(state: BeaconState,
                                       slot: Slot,
                                       subcommittee_index: uint64,
                                       privkey: int) -> BLSSignature:
    domain = get_domain(state, DOMAIN_SYNC_COMMITTEE_SELECTION_PROOF, compute_epoch_at_slot(slot))
    signing_data = SyncAggregatorSelectionData(
        slot=slot,
        subcommittee_index=subcommittee_index,
    )
    signing_root = compute_signing_root(signing_data, domain)
    return bls.Sign(privkey, signing_root)
```

```python
def is_sync_committee_aggregator(signature: BLSSignature) -> bool:
    modulo = max(1, SYNC_COMMITTEE_SIZE // SYNC_COMMITTEE_SUBNET_COUNT // TARGET_AGGREGATORS_PER_SYNC_SUBCOMMITTEE)
    return bytes_to_uint64(hash(signature)[0:8]) % modulo == 0
```

*NOTE*: The set of aggregators generally changes every slot; however, the assignments can be computed ahead of time as soon as the committee is known.

##### Construct sync committee contribution

If a validator is selected to aggregate the `SyncCommitteeMessage`s produced on a subnet during a given `slot`, they construct an aggregated `SyncCommitteeContribution`.

Collect all of the (valid) `sync_committee_messages: Set[SyncCommitteeMessage]` from the `sync_committee_{subnet_id}` gossip during the selected `slot` with an equivalent `beacon_block_root` to that of the aggregator. If `len(sync_committee_messages) > 0`, the aggregator creates a `contribution: SyncCommitteeContribution` with the following fields:

###### Slot

Set `contribution.slot = state.slot` where `state` is the `BeaconState` for the slot in question.

###### Beacon block root

Set `contribution.beacon_block_root = beacon_block_root` from the `beacon_block_root` found in the `sync_committee_messages`.

###### Subcommittee index

Set `contribution.subcommittee_index` to the index for the subcommittee index corresponding to the subcommittee assigned to this subnet. This index matches the `subnet_id` used to derive the topic name.

###### Aggregation bits

Let `contribution.aggregation_bits` be a `Bitvector[SYNC_COMMITTEE_SIZE // SYNC_COMMITTEE_SUBNET_COUNT]`, where the `index`th bit is set in the `Bitvector` for each corresponding validator included in this aggregate from the corresponding subcommittee.
An aggregator finds the index in the sync committee (as determined by a reverse pubkey lookup on `state.current_sync_committee.pubkeys`) for a given validator referenced by `sync_committee_message.validator_index` and maps the sync committee index to an index in the subcommittee (along with the prior `subcommittee_index`). This index within the subcommittee is set in `contribution.aggegration_bits`.

For example, if a validator with index `2044` is pseudo-randomly sampled to sync committee index `135`. This sync committee index maps to `subcommittee_index` `1` with position `7` in the `Bitvector` for the contribution.

*Note*: A validator **could be included multiple times** in a given subcommittee such that multiple bits are set for a single `SyncCommitteeMessage`.

###### Signature

Set `contribution.signature = aggregate_signature` where `aggregate_signature` is obtained by assembling the appropriate collection of `BLSSignature`s from the set of `sync_committee_messages` and using the `bls.Aggregate()` function to produce an aggregate `BLSSignature`.

The collection of input signatures should include one signature per validator who had a bit set in the `aggregation_bits` bitfield, with repeated signatures if one validator maps to multiple indices within the subcommittee.

##### Broadcast sync committee contribution

If the validator is selected to aggregate (`is_sync_committee_aggregator()`), then they broadcast their best aggregate as a `SignedContributionAndProof` to the global aggregate channel (`sync_committee_contribution_and_proof` topic) two-thirds of the way through the `slot`-that is, `SECONDS_PER_SLOT * 2 / INTERVALS_PER_SLOT` seconds after the start of `slot`.

Selection proofs are provided in `ContributionAndProof` to prove to the gossip channel that the validator has been selected as an aggregator.

`ContributionAndProof` messages are signed by the aggregator and broadcast inside of `SignedContributionAndProof` objects to prevent a class of DoS attacks and message forgeries.

First, `contribution_and_proof = get_contribution_and_proof(state, validator_index, contribution, privkey)` is constructed.

```python
def get_contribution_and_proof(state: BeaconState,
                               aggregator_index: ValidatorIndex,
                               contribution: SyncCommitteeContribution,
                               privkey: int) -> ContributionAndProof:
    selection_proof = get_sync_committee_selection_proof(
        state,
        contribution.slot,
        contribution.subcommittee_index,
        privkey,
    )
    return ContributionAndProof(
        aggregator_index=aggregator_index,
        contribution=contribution,
        selection_proof=selection_proof,
    )
```

Then `signed_contribution_and_proof = SignedContributionAndProof(message=contribution_and_proof, signature=signature)` is constructed and broadcast. Where `signature` is obtained from:

```python
def get_contribution_and_proof_signature(state: BeaconState,
                                         contribution_and_proof: ContributionAndProof,
                                         privkey: int) -> BLSSignature:
    contribution = contribution_and_proof.contribution
    domain = get_domain(state, DOMAIN_CONTRIBUTION_AND_PROOF, compute_epoch_at_slot(contribution.slot))
    signing_root = compute_signing_root(contribution_and_proof, domain)
    return bls.Sign(privkey, signing_root)
```

## How to avoid slashing

"Slashing" is the burning of some amount of validator funds and immediate ejection from the active validator set. There are two ways in which funds can be slashed: [proposer slashing](#proposer-slashing) and [attester slashing](#attester-slashing). Although being slashed has serious repercussions, it is simple enough to avoid being slashed all together by remaining *consistent* with respect to the messages a validator has previously signed.

*Note*: Signed data must be within a sequential `Fork` context to conflict. Messages cannot be slashed across diverging forks. If the previous fork version is 1 and the chain splits into fork 2 and 102, messages from 1 can be slashable against messages in forks 1, 2, and 102. Messages in 2 cannot be slashable against messages in 102, and vice versa.

### Proposer slashing

To avoid "proposer slashings", a validator must not sign two conflicting [`BeaconBlock`](./beacon-chain.md#beaconblock) where conflicting is defined as two distinct blocks within the same slot.

*In Phase 0, as long as the validator does not sign two different beacon blocks for the same slot, the validator is safe against proposer slashings.*

Specifically, when signing a `BeaconBlock`, a validator should perform the following steps in the following order:

1. Save a record to hard disk that a beacon block has been signed for the `slot=block.slot`.
2. Generate and broadcast the block.

If the software crashes at some point within this routine, then when the validator comes back online, the hard disk has the record of the *potentially* signed/broadcast block and can effectively avoid slashing.

### Attester slashing

To avoid "attester slashings", a validator must not sign two conflicting [`AttestationData`](./beacon-chain.md#attestationdata) objects, i.e. two attestations that satisfy [`is_slashable_attestation_data`](./beacon-chain.md#is_slashable_attestation_data).

Specifically, when signing an `Attestation`, a validator should perform the following steps in the following order:

1. Save a record to hard disk that an attestation has been signed for source (i.e. `attestation_data.source.epoch`) and target (i.e. `attestation_data.target.epoch`).
2. Generate and broadcast attestation.

If the software crashes at some point within this routine, then when the validator comes back online, the hard disk has the record of the *potentially* signed/broadcast attestation and can effectively avoid slashing.

## Protection best practices

A validator client should be considered standalone and should consider the beacon node as untrusted. This means that the validator client should protect:

1) Private keys -- private keys should be protected from being exported accidentally or by an attacker.
2) Slashing -- before a validator client signs a message it should validate the data, check it against a local slashing database (do not sign a slashable attestation or block) and update its internal slashing database with the newly signed object.
3) Recovered validator -- Recovering a validator from a private key will result in an empty local slashing db. Best practice is to import (from a trusted source) that validator's attestation history. See [EIP 3076](https://github.com/ethereum/EIPs/pull/3076/files) for a standard slashing interchange format.
4) Far future signing requests -- A validator client can be requested to sign a far into the future attestation, resulting in a valid non-slashable request. If the validator client signs this message, it will result in it blocking itself from attesting any other attestation until the beacon-chain reaches that far into the future epoch. This will result in an inactivity penalty and potential ejection due to low balance.
A validator client should prevent itself from signing such requests by: a) keeping a local time clock if possible and following best practices to stop time server attacks and b) refusing to sign, by default, any message that has a large (>6h) gap from the current slashing protection database indicated a time "jump" or a long offline event. The administrator can manually override this protection to restart the validator after a genuine long offline event.

## Sync committee subnet stability

The sync committee subnets need special care to ensure stability given the relatively low number of validators involved in the sync committee at any particular time.
To provide this stability, a validator must do the following:

- Maintain advertisement of the subnet the validator in the sync committee is assigned to in their node's ENR as soon as they have joined the subnet.
Subnet assignments are known `EPOCHS_PER_SYNC_COMMITTEE_PERIOD` epochs in advance and can be computed with `compute_subnets_for_sync_committee` defined above.
ENR advertisement is indicated by setting the appropriate bit(s) of the bitfield found under the `syncnets` key in the ENR corresponding to the derived `subnet_id`(s).
Any bits modified for the sync committee responsibilities are unset in the ENR once the node no longer has any validators in the subcommittee.

  *Note*: The first sync committee from phase 0 to the Altair fork will not be known until the fork happens, which implies subnet assignments are not known until then.
Early sync committee members should listen for topic subscriptions from peers and employ discovery via the ENR advertisements near the fork boundary to form initial subnets.
Some early sync committee rewards may be missed while the initial subnets form.

- To join a sync committee subnet, select a random number of epochs before the end of the current sync committee period between 1 and `SYNC_COMMITTEE_SUBNET_COUNT`, inclusive.
Validators should join their member subnet at the beginning of the epoch they have randomly selected.
For example, if the next sync committee period starts at epoch `853,248` and the validator randomly selects an offset of `3`, they should join the subnet at the beginning of epoch `853,245`.
Validators should leverage the lookahead period on sync committee assignments so that they can join the appropriate subnets ahead of their assigned sync committee period.

## Enabling validator withdrawals

Validator balances are withdrawn periodically via an automatic process. For exited validators, the full balance is withdrawn. For active validators, the balance in excess of `MAX_EFFECTIVE_BALANCE` is withdrawn.

There is one prerequisite for this automated process:
the validator's withdrawal credentials pointing to an execution layer address, i.e. having an `ETH1_ADDRESS_WITHDRAWAL_PREFIX`.

If a validator has a `BLS_WITHDRAWAL_PREFIX` withdrawal credential prefix, to participate in withdrawals the validator must 
create a one-time message to change their withdrawal credential from the version authenticated with a BLS key to the
version compatible with the execution layer. This message -- a `BLSToExecutionChange` -- is available starting in Capella

Validators who wish to enable withdrawals **MUST** assemble, sign, and broadcast this message so that it is accepted
on the beacon chain. Validators who do not want to enable withdrawals and have the `BLS_WITHDRAWAL_PREFIX` version of
withdrawal credentials can delay creating this message until they are ready to enable withdrawals.
