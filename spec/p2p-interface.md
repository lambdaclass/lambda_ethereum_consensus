# Networking

This document contains the networking specification for Phase 0.

It consists of four main sections:

1. A specification of the network fundamentals.
2. A specification of the three network interaction *domains* of the proof-of-stake consensus layer: (a) the gossip domain, (b) the discovery domain, and (c) the Req/Resp domain.
3. The rationale and further explanation for the design choices made in the previous two sections.
4. An analysis of the maturity/state of the libp2p features required by this spec across the languages in which clients are being developed.

## Table of contents
<!-- TOC -->
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Network fundamentals](#network-fundamentals)
  - [Transport](#transport)
  - [Encryption and identification](#encryption-and-identification)
  - [Protocol Negotiation](#protocol-negotiation)
  - [Multiplexing](#multiplexing)
- [Consensus-layer network interaction domains](#consensus-layer-network-interaction-domains)
  - [Custom types](#custom-types)
  - [Constants](#constants)
  - [Configuration](#configuration)
  - [MetaData](#metadata)
  - [The gossip domain: gossipsub](#the-gossip-domain-gossipsub)
    - [Topics and messages](#topics-and-messages)
      - [Global topics](#global-topics)
        - [`beacon_block`](#beacon_block)
        - [`beacon_aggregate_and_proof`](#beacon_aggregate_and_proof)
        - [`bls_to_execution_change`](#bls_to_execution_change)
        - [`voluntary_exit`](#voluntary_exit)
        - [`proposer_slashing`](#proposer_slashing)
        - [`attester_slashing`](#attester_slashing)
      - [Attestation subnets](#attestation-subnets)
        - [`beacon_attestation_{subnet_id}`](#beacon_attestation_subnet_id)
      - [Attestations and Aggregation](#attestations-and-aggregation)
    - [Encodings](#encodings)
  - [The Req/Resp domain](#the-reqresp-domain)
    - [Protocol identification](#protocol-identification)
    - [Req/Resp interaction](#reqresp-interaction)
      - [Requesting side](#requesting-side)
      - [Responding side](#responding-side)
    - [Encoding strategies](#encoding-strategies)
      - [SSZ-snappy encoding strategy](#ssz-snappy-encoding-strategy)
    - [Messages](#messages)
      - [Status](#status)
      - [Goodbye](#goodbye)
      - [BeaconBlocksByRange](#beaconblocksbyrange)
      - [BeaconBlocksByRoot](#beaconblocksbyroot)
      - [Ping](#ping)
      - [GetMetaData](#getmetadata)
  - [The discovery domain: discv5](#the-discovery-domain-discv5)
    - [Integration into libp2p stacks](#integration-into-libp2p-stacks)
    - [ENR structure](#enr-structure)
      - [Attestation subnet bitfield](#attestation-subnet-bitfield)
      - [`eth2` field](#eth2-field)
  - [Attestation subnet subscription](#attestation-subnet-subscription)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->
<!-- /TOC -->

## Network fundamentals

This section outlines the specification for the networking stack in Ethereum consensus-layer clients.

### Transport

Even though libp2p is a multi-transport stack (designed to listen on multiple simultaneous transports and endpoints transparently),
we hereby define a profile for basic interoperability.

All implementations MUST support the TCP libp2p transport, and it MUST be enabled for both dialing and listening (i.e. outbound and inbound connections).
The libp2p TCP transport supports listening on IPv4 and IPv6 addresses (and on multiple simultaneously).

Clients must support listening on at least one of IPv4 or IPv6.
Clients that do _not_ have support for listening on IPv4 SHOULD be cognizant of the potential disadvantages in terms of
Internet-wide routability/support. Clients MAY choose to listen only on IPv6, but MUST be capable of dialing both IPv4 and IPv6 addresses.

All listening endpoints must be publicly dialable, and thus not rely on libp2p circuit relay, AutoNAT, or AutoRelay facilities.
(Usage of circuit relay, AutoNAT, or AutoRelay will be specifically re-examined soon.)

Nodes operating behind a NAT, or otherwise undialable by default (e.g. container runtime, firewall, etc.),
MUST have their infrastructure configured to enable inbound traffic on the announced public listening endpoint.

### Encryption and identification

The [Libp2p-noise](https://github.com/libp2p/specs/tree/master/noise) secure
channel handshake with `secp256k1` identities will be used for encryption.

As specified in the libp2p specification, clients MUST support the `XX` handshake pattern.

### Protocol Negotiation

Clients MUST use exact equality when negotiating protocol versions to use and MAY use the version to give priority to higher version numbers.

Clients MUST support [multistream-select 1.0](https://github.com/multiformats/multistream-select/)
and MAY support [multiselect 2.0](https://github.com/libp2p/specs/pull/95) when the spec solidifies.
Once all clients have implementations for multiselect 2.0, multistream-select 1.0 MAY be phased out.

### Multiplexing

During connection bootstrapping, libp2p dynamically negotiates a mutually supported multiplexing method to conduct parallel conversations.
This applies to transports that are natively incapable of multiplexing (e.g. TCP, WebSockets, WebRTC),
and is omitted for capable transports (e.g. QUIC).

Two multiplexers are commonplace in libp2p implementations:
[mplex](https://github.com/libp2p/specs/tree/master/mplex) and [yamux](https://github.com/hashicorp/yamux/blob/master/spec.md).
Their protocol IDs are, respectively: `/mplex/6.7.0` and `/yamux/1.0.0`.

Clients MUST support [mplex](https://github.com/libp2p/specs/tree/master/mplex)
and MAY support [yamux](https://github.com/hashicorp/yamux/blob/master/spec.md).
If both are supported by the client, yamux MUST take precedence during negotiation.
See the [Rationale](#design-decision-rationale) section below for tradeoffs.

## Consensus-layer network interaction domains

### Custom types

We define the following Python custom types for type hinting and readability:

| Name | SSZ equivalent | Description |
| - | - | - |
| `NodeID`   | `uint256` | node identifier   |
| `SubnetID` | `uint64`  | subnet identifier |

### Constants

| Name | Value | Unit | Duration |
| - | - | :-: | :-: |
| `NODE_ID_BITS` | `256` | The bit length of uint256 is 256 |

### Configuration

This section outlines configurations that are used in this spec.

| Name | Value | Description |
|---|---|---|
| `GOSSIP_MAX_SIZE` | `10 * 2**20` (= 10485760, 10 MiB) | The maximum allowed size of uncompressed gossip messages. |
| `MAX_REQUEST_BLOCKS` | `2**10` (= 1024) | Maximum number of blocks in a single request |
| `EPOCHS_PER_SUBNET_SUBSCRIPTION` | `2**8` (= 256) | Number of epochs on a subnet subscription (~27 hours) |
| `MIN_EPOCHS_FOR_BLOCK_REQUESTS` | `MIN_VALIDATOR_WITHDRAWABILITY_DELAY + CHURN_LIMIT_QUOTIENT // 2` (= 33024, ~5 months) | The minimum epoch range over which a node must serve blocks |
| `MAX_CHUNK_SIZE` | `10 * 2**20` (=10485760, 10 MiB) | The maximum allowed size of uncompressed req/resp chunked responses. |
| `TTFB_TIMEOUT` | `5` | The maximum duration in **seconds** to wait for first byte of request response (time-to-first-byte). |
| `RESP_TIMEOUT` | `10` | The maximum duration in **seconds** for complete response transfer. |
| `ATTESTATION_PROPAGATION_SLOT_RANGE` | `32` | The maximum number of slots during which an attestation can be propagated. |
| `MAXIMUM_GOSSIP_CLOCK_DISPARITY` | `500` | The maximum **milliseconds** of clock disparity assumed between honest nodes. |
| `MESSAGE_DOMAIN_INVALID_SNAPPY` | `DomainType('0x00000000')` | 4-byte domain for gossip message-id isolation of *invalid* snappy messages |
| `MESSAGE_DOMAIN_VALID_SNAPPY`  | `DomainType('0x01000000')` | 4-byte domain for gossip message-id isolation of *valid* snappy messages |
| `SUBNETS_PER_NODE` | `2` | The number of long-lived subnets a beacon node should be subscribed to. |
| `ATTESTATION_SUBNET_COUNT` | `2**6` (= 64) | The number of attestation subnets used in the gossipsub protocol. |
| `ATTESTATION_SUBNET_EXTRA_BITS` | `0` | The number of extra bits of a NodeId to use when mapping to a subscribed subnet |
| `ATTESTATION_SUBNET_PREFIX_BITS` | `int(ceillog2(ATTESTATION_SUBNET_COUNT) + ATTESTATION_SUBNET_EXTRA_BITS)` | |

### MetaData

Clients MUST locally store the following `MetaData`:

```
(
  seq_number: uint64
  attnets: Bitvector[ATTESTATION_SUBNET_COUNT]
  syncnets: Bitvector[SYNC_COMMITTEE_SUBNET_COUNT]
)
```

Where

- `seq_number` is a `uint64` starting at `0` used to version the node's metadata.
  If any other field in the local `MetaData` changes, the node MUST increment `seq_number` by 1.
- `attnets` is a `Bitvector` representing the node's persistent attestation subnet subscriptions.
- `syncnets` is a `Bitvector` representing the node's sync committee subnet subscriptions. This field should mirror the data in the node's ENR as outlined in the [validator guide](https://github.com/ethereum/consensus-specs/blob/dev/specs/altair/validator.md#sync-committee-subnet-stability).

*Note*: `MetaData.seq_number` is used for versioning of the node's metadata,
is entirely independent of the ENR sequence number,
and will in most cases be out of sync with the ENR sequence number.

### The gossip domain: gossipsub

Clients MUST support the [gossipsub v1](https://github.com/libp2p/specs/blob/master/pubsub/gossipsub/gossipsub-v1.0.md) libp2p Protocol
including the [gossipsub v1.1](https://github.com/libp2p/specs/blob/master/pubsub/gossipsub/gossipsub-v1.1.md) extension.

**Protocol ID:** `/meshsub/1.1.0`

**Gossipsub Parameters**

The following gossipsub [parameters](https://github.com/libp2p/specs/blob/master/pubsub/gossipsub/gossipsub-v1.0.md#parameters) will be used:

- `D` (topic stable mesh target count): 8
- `D_low` (topic stable mesh low watermark): 6
- `D_high` (topic stable mesh high watermark): 12
- `D_lazy` (gossip target): 6
- `heartbeat_interval` (frequency of heartbeat, seconds): 0.7
- `fanout_ttl` (ttl for fanout maps for topics we are not subscribed to but have published to, seconds): 60
- `mcache_len` (number of windows to retain full messages in cache for `IWANT` responses): 6
- `mcache_gossip` (number of windows to gossip about): 3
- `seen_ttl` (number of heartbeat intervals to retain message IDs): 550

*Note*: Gossipsub v1.1 introduces a number of
[additional parameters](https://github.com/libp2p/specs/blob/master/pubsub/gossipsub/gossipsub-v1.1.md#overview-of-new-parameters)
for peer scoring and other attack mitigations.
These are currently under investigation and will be spec'd and released to mainnet when they are ready.

#### Topics and messages

Topics are plain UTF-8 strings and are encoded on the wire as determined by protobuf (gossipsub messages are enveloped in protobuf messages).
Topic strings have form: `/eth2/ForkDigestValue/Name/Encoding`.
This defines both the type of data being sent on the topic and how the data field of the message is encoded.

- `ForkDigestValue` - the lowercase hex-encoded (no "0x" prefix) bytes of `compute_fork_digest(current_fork_version, genesis_validators_root)` where
    - `current_fork_version` is the fork version of the epoch of the message to be sent on the topic
    - `genesis_validators_root` is the static `Root` found in `state.genesis_validators_root`
- `Name` - see table below
- `Encoding` - the encoding strategy describes a specific representation of bytes that will be transmitted over the wire.
  See the [Encodings](#Encodings) section for further details.

*Note*: `ForkDigestValue` is composed of values that are not known until the genesis block/state are available.
Due to this, clients SHOULD NOT subscribe to gossipsub topics until these genesis values are known.

Each gossipsub [message](https://github.com/libp2p/go-libp2p-pubsub/blob/master/pb/rpc.proto#L17-L24) has a maximum size of `GOSSIP_MAX_SIZE`.
Clients MUST reject (fail validation) messages that are over this size limit.
Likewise, clients MUST NOT emit or propagate messages larger than this limit.

The optional `from` (1), `seqno` (3), `signature` (5) and `key` (6) protobuf fields are omitted from the message,
since messages are identified by content, anonymous, and signed where necessary in the application layer.
Starting from Gossipsub v1.1, clients MUST enforce this by applying the `StrictNoSign`
[signature policy](https://github.com/libp2p/specs/blob/master/pubsub/README.md#signature-policy-options).

The `message-id` of a gossipsub message MUST be the following 20 byte value computed from the message data:
* If `message.data` has a valid snappy decompression, set `message-id` to the first 20 bytes of the `SHA256` hash of
  the concatenation of `MESSAGE_DOMAIN_VALID_SNAPPY` with the snappy decompressed message data,
  i.e. `SHA256(MESSAGE_DOMAIN_VALID_SNAPPY + snappy_decompress(message.data))[:20]`.
* Otherwise, set `message-id` to the first 20 bytes of the `SHA256` hash of
  the concatenation of `MESSAGE_DOMAIN_INVALID_SNAPPY` with the raw message data,
  i.e. `SHA256(MESSAGE_DOMAIN_INVALID_SNAPPY + message.data)[:20]`.

*Note*: The above logic handles two exceptional cases:
(1) multiple snappy `data` can decompress to the same value,
and (2) some message `data` can fail to snappy decompress altogether.

The derivation of the `message-id` has changed starting with Altair to incorporate the message `topic` along with the message `data`. These are fields of the `Message` Protobuf, and interpreted as empty byte strings if missing.
The `message-id` MUST be the following 20 byte value computed from the message:
* If `message.data` has a valid snappy decompression, set `message-id` to the first 20 bytes of the `SHA256` hash of
  the concatenation of the following data: `MESSAGE_DOMAIN_VALID_SNAPPY`, the length of the topic byte string (encoded as little-endian `uint64`),
  the topic byte string, and the snappy decompressed message data:
  i.e. `SHA256(MESSAGE_DOMAIN_VALID_SNAPPY + uint_to_bytes(uint64(len(message.topic))) + message.topic + snappy_decompress(message.data))[:20]`.
* Otherwise, set `message-id` to the first 20 bytes of the `SHA256` hash of
  the concatenation of the following data: `MESSAGE_DOMAIN_INVALID_SNAPPY`, the length of the topic byte string (encoded as little-endian `uint64`),
  the topic byte string, and the raw message data:
  i.e. `SHA256(MESSAGE_DOMAIN_INVALID_SNAPPY + uint_to_bytes(uint64(len(message.topic))) + message.topic + message.data)[:20]`.

Implementations may need to carefully handle the function that computes the `message-id`. In particular, messages on topics with the Phase 0
fork digest should use the `message-id` procedure specified in the Phase 0 document.
Messages on topics with the Altair fork digest should use the `message-id` procedure defined here.
If an implementation only supports a single `message-id` function, it can define a switch inline;
for example, `if topic in phase0_topics: return phase0_msg_id_fn(message) else return altair_msg_id_fn(message)`.

The payload is carried in the `data` field of a gossipsub message, and varies depending on the topic:

| Name                             | Message Type              |
|----------------------------------|---------------------------|
| `beacon_block`                   | `SignedBeaconBlock`       |
| `beacon_aggregate_and_proof`     | `SignedAggregateAndProof` |
| `beacon_attestation_{subnet_id}` | `Attestation`             |
| `voluntary_exit`                 | `SignedVoluntaryExit`     |
| `proposer_slashing`              | `ProposerSlashing`        |
| `attester_slashing`              | `AttesterSlashing`        |

Altair topics:

| Name | Message Type |
| - | - |
| `beacon_block` | `SignedBeaconBlock` (modified) |
| `sync_committee_contribution_and_proof` | `SignedContributionAndProof` |
| `sync_committee_{subnet_id}` | `SyncCommitteeMessage` |

Bellatrix:

| Name | Message Type |
| - | - |
| `beacon_block` | `SignedBeaconBlock` (modified) |

Capella:

| Name | Message Type |
| - | - |
| `beacon_block` | `SignedBeaconBlock` (modified) |
| `bls_to_execution_change` | `SignedBLSToExecutionChange` |

Note that the `ForkDigestValue` path segment of the topic separates the old and the new `beacon_block` topics.

Clients MUST reject (fail validation) messages containing an incorrect type, or invalid payload.

When processing incoming gossip, clients MAY descore or disconnect peers who fail to observe these constraints.

For any optional queueing, clients SHOULD maintain maximum queue sizes to avoid DoS vectors.

Gossipsub v1.1 introduces [Extended Validators](https://github.com/libp2p/specs/blob/master/pubsub/gossipsub/gossipsub-v1.1.md#extended-validators)
for the application to aid in the gossipsub peer-scoring scheme.
We utilize `ACCEPT`, `REJECT`, and `IGNORE`. For each gossipsub topic, there are application specific validations.
If all validations pass, return `ACCEPT`.
If one or more validations fail while processing the items in order, return either `REJECT` or `IGNORE` as specified in the prefix of the particular condition.

##### Global topics

There are two primary global topics used to propagate beacon blocks (`beacon_block`)
and aggregate attestations (`beacon_aggregate_and_proof`) to all nodes on the network.

There are three additional global topics that are used to propagate lower frequency validator messages
(`voluntary_exit`, `proposer_slashing`, and `attester_slashing`).

###### `beacon_block`

The `beacon_block` topic is used solely for propagating new signed beacon blocks to all nodes on the networks.
Signed blocks are sent in their entirety.

Modified in Altair due to the inner `BeaconBlockBody` change.

The following validations MUST pass before forwarding the `signed_beacon_block` on the network.
- _[IGNORE]_ The block is not from a future slot (with a `MAXIMUM_GOSSIP_CLOCK_DISPARITY` allowance) --
  i.e. validate that `signed_beacon_block.message.slot <= current_slot`
  (a client MAY queue future blocks for processing at the appropriate slot).
- _[IGNORE]_ The block is from a slot greater than the latest finalized slot --
  i.e. validate that `signed_beacon_block.message.slot > compute_start_slot_at_epoch(state.finalized_checkpoint.epoch)`
  (a client MAY choose to validate and store such blocks for additional purposes -- e.g. slashing detection, archive nodes, etc).
- _[IGNORE]_ The block is the first block with valid signature received for the proposer for the slot, `signed_beacon_block.message.slot`.
- _[REJECT]_ The proposer signature, `signed_beacon_block.signature`, is valid with respect to the `proposer_index` pubkey.
- _[IGNORE]_ The block's parent (defined by `block.parent_root`) has been seen
  (via both gossip and non-gossip sources)
  (a client MAY queue blocks for processing once the parent block is retrieved).
- _[REJECT]_ The block's parent (defined by `block.parent_root`) passes validation.
- _[REJECT]_ The block is from a higher slot than its parent.
- _[REJECT]_ The current `finalized_checkpoint` is an ancestor of `block` -- i.e.
  `get_checkpoint_block(store, block.parent_root, store.finalized_checkpoint.epoch)
  == store.finalized_checkpoint.root`
- _[REJECT]_ The block is proposed by the expected `proposer_index` for the block's slot
  in the context of the current shuffling (defined by `parent_root`/`slot`).
  If the `proposer_index` cannot immediately be verified against the expected shuffling,
  the block MAY be queued for later processing while proposers for the block's branch are calculated --
  in such a case _do not_ `REJECT`, instead `IGNORE` this message.

Modified in Bellatrix due to the inner `BeaconBlockBody` change.

In addition to the gossip validations for this topic from prior specifications,
the following validations MUST pass before forwarding the `signed_beacon_block` on the network.
Alias `block = signed_beacon_block.message`, `execution_payload = block.body.execution_payload`.

- If the execution is enabled for the block -- i.e. `is_execution_enabled(state, block.body)`
  then validate the following:
  - _[REJECT]_ The block's execution payload timestamp is correct with respect to the slot
      -- i.e. `execution_payload.timestamp == compute_timestamp_at_slot(state, block.slot)`.
  - If `exection_payload` verification of block's parent by an execution node is *not* complete:
    - [REJECT] The block's parent (defined by `block.parent_root`) passes all
      validation (excluding execution node verification of the `block.body.execution_payload`).
  - otherwise:
    - [IGNORE] The block's parent (defined by `block.parent_root`) passes all
      validation (including execution node verification of the `block.body.execution_payload`).

The following gossip validation from prior specifications MUST NOT be applied if the execution is enabled for the block -- i.e. `is_execution_enabled(state, block.body)`:

  - [REJECT] The block's parent (defined by `block.parent_root`) passes validation.

Modified in Capella:
The *type* of the payload of this topic changes to the (modified) `SignedBeaconBlock` found in Capella.
Specifically, this type changes with the addition of `bls_to_execution_changes` to the inner `BeaconBlockBody`.

###### `beacon_aggregate_and_proof`

The `beacon_aggregate_and_proof` topic is used to propagate aggregated attestations (as `SignedAggregateAndProof`s)
to subscribing nodes (typically validators) to be included in future blocks.

The following validations MUST pass before forwarding the `signed_aggregate_and_proof` on the network.
(We define the following for convenience -- `aggregate_and_proof = signed_aggregate_and_proof.message` and `aggregate = aggregate_and_proof.aggregate`)
- _[IGNORE]_ `aggregate.data.slot` is within the last `ATTESTATION_PROPAGATION_SLOT_RANGE` slots (with a `MAXIMUM_GOSSIP_CLOCK_DISPARITY` allowance) --
  i.e. `aggregate.data.slot + ATTESTATION_PROPAGATION_SLOT_RANGE >= current_slot >= aggregate.data.slot`
  (a client MAY queue future aggregates for processing at the appropriate slot).
- _[REJECT]_ The aggregate attestation's epoch matches its target -- i.e. `aggregate.data.target.epoch ==
  compute_epoch_at_slot(aggregate.data.slot)`
- _[IGNORE]_ A valid aggregate attestation defined by `hash_tree_root(aggregate.data)` whose `aggregation_bits` is a non-strict superset has _not_ already been seen.
  (via aggregate gossip, within a verified block, or through the creation of an equivalent aggregate locally).
- _[IGNORE]_ The `aggregate` is the first valid aggregate received for the aggregator
  with index `aggregate_and_proof.aggregator_index` for the epoch `aggregate.data.target.epoch`.
- _[REJECT]_ The attestation has participants --
  that is, `len(get_attesting_indices(state, aggregate.data, aggregate.aggregation_bits)) >= 1`.
- _[REJECT]_ `aggregate_and_proof.selection_proof` selects the validator as an aggregator for the slot --
  i.e. `is_aggregator(state, aggregate.data.slot, aggregate.data.index, aggregate_and_proof.selection_proof)` returns `True`.
- _[REJECT]_ The aggregator's validator index is within the committee --
  i.e. `aggregate_and_proof.aggregator_index in get_beacon_committee(state, aggregate.data.slot, aggregate.data.index)`.
- _[REJECT]_ The `aggregate_and_proof.selection_proof` is a valid signature
  of the `aggregate.data.slot` by the validator with index `aggregate_and_proof.aggregator_index`.
- _[REJECT]_ The aggregator signature, `signed_aggregate_and_proof.signature`, is valid.
- _[REJECT]_ The signature of `aggregate` is valid.
- _[IGNORE]_ The block being voted for (`aggregate.data.beacon_block_root`) has been seen
  (via both gossip and non-gossip sources)
  (a client MAY queue aggregates for processing once block is retrieved).
- _[REJECT]_ The block being voted for (`aggregate.data.beacon_block_root`) passes validation.
- _[IGNORE]_ The current `finalized_checkpoint` is an ancestor of the `block` defined by `aggregate.data.beacon_block_root` -- i.e.
  `get_checkpoint_block(store, aggregate.data.beacon_block_root, finalized_checkpoint.epoch)
  == store.finalized_checkpoint.root`

###### `bls_to_execution_change`

(Added in Capella)

This topic is used to propagate signed bls to execution change messages to be included in future blocks.

The following validations MUST pass before forwarding the `signed_bls_to_execution_change` on the network:

- _[IGNORE]_ `current_epoch >= CAPELLA_FORK_EPOCH`,
  where `current_epoch` is defined by the current wall-clock time.
- _[IGNORE]_ The `signed_bls_to_execution_change` is the first valid signed bls to execution change received
  for the validator with index `signed_bls_to_execution_change.message.validator_index`.
- _[REJECT]_ All of the conditions within `process_bls_to_execution_change` pass validation.

###### `voluntary_exit`

The `voluntary_exit` topic is used solely for propagating signed voluntary validator exits to proposers on the network.
Signed voluntary exits are sent in their entirety.

The following validations MUST pass before forwarding the `signed_voluntary_exit` on to the network.
- _[IGNORE]_ The voluntary exit is the first valid voluntary exit received
  for the validator with index `signed_voluntary_exit.message.validator_index`.
- _[REJECT]_ All of the conditions within `process_voluntary_exit` pass validation.

###### `proposer_slashing`

The `proposer_slashing` topic is used solely for propagating proposer slashings to proposers on the network.
Proposer slashings are sent in their entirety.

The following validations MUST pass before forwarding the `proposer_slashing` on to the network.
- _[IGNORE]_ The proposer slashing is the first valid proposer slashing received
  for the proposer with index `proposer_slashing.signed_header_1.message.proposer_index`.
- _[REJECT]_ All of the conditions within `process_proposer_slashing` pass validation.

###### `attester_slashing`

The `attester_slashing` topic is used solely for propagating attester slashings to proposers on the network.
Attester slashings are sent in their entirety.

Clients who receive an attester slashing on this topic MUST validate the conditions within `process_attester_slashing` before forwarding it across the network.
- _[IGNORE]_ At least one index in the intersection of the attesting indices of each attestation
  has not yet been seen in any prior `attester_slashing`
  (i.e. `attester_slashed_indices = set(attestation_1.attesting_indices).intersection(attestation_2.attesting_indices)`,
  verify if `any(attester_slashed_indices.difference(prior_seen_attester_slashed_indices))`).
- _[REJECT]_ All of the conditions within `process_attester_slashing` pass validation.

###### `sync_committee_contribution_and_proof`

This topic is used to propagate partially aggregated sync committee messages to be included in future blocks.

The following validations MUST pass before forwarding the `signed_contribution_and_proof` on the network; define `contribution_and_proof = signed_contribution_and_proof.message`, `contribution = contribution_and_proof.contribution`, and the following function `get_sync_subcommittee_pubkeys` for convenience:

```python
def get_sync_subcommittee_pubkeys(state: BeaconState, subcommittee_index: uint64) -> Sequence[BLSPubkey]:
    # Committees assigned to `slot` sign for `slot - 1`
    # This creates the exceptional logic below when transitioning between sync committee periods
    next_slot_epoch = compute_epoch_at_slot(Slot(state.slot + 1))
    if compute_sync_committee_period(get_current_epoch(state)) == compute_sync_committee_period(next_slot_epoch):
        sync_committee = state.current_sync_committee
    else:
        sync_committee = state.next_sync_committee

    # Return pubkeys for the subcommittee index
    sync_subcommittee_size = SYNC_COMMITTEE_SIZE // SYNC_COMMITTEE_SUBNET_COUNT
    i = subcommittee_index * sync_subcommittee_size
    return sync_committee.pubkeys[i:i + sync_subcommittee_size]
```

- _[IGNORE]_ The contribution's slot is for the current slot (with a `MAXIMUM_GOSSIP_CLOCK_DISPARITY` allowance), i.e. `contribution.slot == current_slot`.
- _[REJECT]_ The subcommittee index is in the allowed range, i.e. `contribution.subcommittee_index < SYNC_COMMITTEE_SUBNET_COUNT`.
- _[REJECT]_ The contribution has participants --
  that is, `any(contribution.aggregation_bits)`.
- _[REJECT]_ `contribution_and_proof.selection_proof` selects the validator as an aggregator for the slot -- i.e. `is_sync_committee_aggregator(contribution_and_proof.selection_proof)` returns `True`.
- _[REJECT]_ The aggregator's validator index is in the declared subcommittee of the current sync committee --
  i.e. `state.validators[contribution_and_proof.aggregator_index].pubkey in get_sync_subcommittee_pubkeys(state, contribution.subcommittee_index)`.
- _[IGNORE]_ A valid sync committee contribution with equal `slot`, `beacon_block_root` and `subcommittee_index` whose `aggregation_bits` is non-strict superset has _not_ already been seen.
- _[IGNORE]_ The sync committee contribution is the first valid contribution received for the aggregator with index `contribution_and_proof.aggregator_index`
  for the slot `contribution.slot` and subcommittee index `contribution.subcommittee_index`
  (this requires maintaining a cache of size `SYNC_COMMITTEE_SIZE` for this topic that can be flushed after each slot).
- _[REJECT]_ The `contribution_and_proof.selection_proof` is a valid signature of the `SyncAggregatorSelectionData` derived from the `contribution` by the validator with index `contribution_and_proof.aggregator_index`.
- _[REJECT]_ The aggregator signature, `signed_contribution_and_proof.signature`, is valid.
- _[REJECT]_ The aggregate signature is valid for the message `beacon_block_root` and aggregate pubkey derived from the participation info in `aggregation_bits` for the subcommittee specified by the `contribution.subcommittee_index`.

##### Attestation subnets

Attestation subnets are used to propagate unaggregated attestations to subsections of the network.

###### `beacon_attestation_{subnet_id}`

The `beacon_attestation_{subnet_id}` topics are used to propagate unaggregated attestations
to the subnet `subnet_id` (typically beacon and persistent committees) to be aggregated before being gossiped to `beacon_aggregate_and_proof`.

The following validations MUST pass before forwarding the `attestation` on the subnet.
- _[REJECT]_ The committee index is within the expected range -- i.e. `data.index < get_committee_count_per_slot(state, data.target.epoch)`.
- _[REJECT]_ The attestation is for the correct subnet --
  i.e. `compute_subnet_for_attestation(committees_per_slot, attestation.data.slot, attestation.data.index) == subnet_id`,
  where `committees_per_slot = get_committee_count_per_slot(state, attestation.data.target.epoch)`,
  which may be pre-computed along with the committee information for the signature check.
- _[IGNORE]_ `attestation.data.slot` is within the last `ATTESTATION_PROPAGATION_SLOT_RANGE` slots
  (within a `MAXIMUM_GOSSIP_CLOCK_DISPARITY` allowance) --
  i.e. `attestation.data.slot + ATTESTATION_PROPAGATION_SLOT_RANGE >= current_slot >= attestation.data.slot`
  (a client MAY queue future attestations for processing at the appropriate slot).
- _[REJECT]_ The attestation's epoch matches its target -- i.e. `attestation.data.target.epoch ==
  compute_epoch_at_slot(attestation.data.slot)`
- _[REJECT]_ The attestation is unaggregated --
  that is, it has exactly one participating validator (`len([bit for bit in attestation.aggregation_bits if bit]) == 1`, i.e. exactly 1 bit is set).
- _[REJECT]_ The number of aggregation bits matches the committee size -- i.e.
  `len(attestation.aggregation_bits) == len(get_beacon_committee(state, data.slot, data.index))`.
- _[IGNORE]_ There has been no other valid attestation seen on an attestation subnet
  that has an identical `attestation.data.target.epoch` and participating validator index.
- _[REJECT]_ The signature of `attestation` is valid.
- _[IGNORE]_ The block being voted for (`attestation.data.beacon_block_root`) has been seen
  (via both gossip and non-gossip sources)
  (a client MAY queue attestations for processing once block is retrieved).
- _[REJECT]_ The block being voted for (`attestation.data.beacon_block_root`) passes validation.
- _[REJECT]_ The attestation's target block is an ancestor of the block named in the LMD vote -- i.e.
  `get_checkpoint_block(store, attestation.data.beacon_block_root, attestation.data.target.epoch) == attestation.data.target.root`
- _[IGNORE]_ The current `finalized_checkpoint` is an ancestor of the `block` defined by `attestation.data.beacon_block_root` -- i.e.
  `get_checkpoint_block(store, attestation.data.beacon_block_root, store.finalized_checkpoint.epoch)
  == store.finalized_checkpoint.root`



##### Attestations and Aggregation

Attestation broadcasting is grouped into subnets defined by a topic.
The number of subnets is defined via `ATTESTATION_SUBNET_COUNT`.
The correct subnet for an attestation can be calculated with `compute_subnet_for_attestation`.
`beacon_attestation_{subnet_id}` topics, are rotated through throughout the epoch in a similar fashion to rotating through shards in committees (future beacon chain upgrade).
The subnets are rotated through with `committees_per_slot = get_committee_count_per_slot(state, attestation.data.target.epoch)` subnets per slot.

Unaggregated attestations are sent as `Attestation`s to the subnet topic,
`beacon_attestation_{compute_subnet_for_attestation(committees_per_slot, attestation.data.slot, attestation.data.index)}` as `Attestation`s.

Aggregated attestations are sent to the `beacon_aggregate_and_proof` topic as `AggregateAndProof`s.

##### Sync committee subnets

Sync committee subnets are used to propagate unaggregated sync committee messages to subsections of the network.

###### `sync_committee_{subnet_id}`

The `sync_committee_{subnet_id}` topics are used to propagate unaggregated sync committee messages to the subnet `subnet_id` to be aggregated before being gossiped to the global `sync_committee_contribution_and_proof` topic.

The following validations MUST pass before forwarding the `sync_committee_message` on the network:

- _[IGNORE]_ The message's slot is for the current slot (with a `MAXIMUM_GOSSIP_CLOCK_DISPARITY` allowance), i.e. `sync_committee_message.slot == current_slot`.
- _[REJECT]_ The `subnet_id` is valid for the given validator, i.e. `subnet_id in compute_subnets_for_sync_committee(state, sync_committee_message.validator_index)`.
  Note this validation implies the validator is part of the broader current sync committee along with the correct subcommittee.
- _[IGNORE]_ There has been no other valid sync committee message for the declared `slot` for the validator referenced by `sync_committee_message.validator_index`
  (this requires maintaining a cache of size `SYNC_COMMITTEE_SIZE // SYNC_COMMITTEE_SUBNET_COUNT` for each subnet that can be flushed after each slot).
  Note this validation is _per topic_ so that for a given `slot`, multiple messages could be forwarded with the same `validator_index` as long as the `subnet_id`s are distinct.
- _[REJECT]_ The `signature` is valid for the message `beacon_block_root` for the validator referenced by `validator_index`.

##### Sync committees and aggregation

The aggregation scheme closely follows the design of the attestation aggregation scheme.
Sync committee messages are broadcast into "subnets" defined by a topic.
The number of subnets is defined by `SYNC_COMMITTEE_SUBNET_COUNT` in the [Altair validator guide](./validator.md#constants).
Sync committee members are divided into "subcommittees" which are then assigned to a subnet for the duration of tenure in the sync committee.
Individual validators can be duplicated in the broader sync committee such that they are included multiple times in a given subcommittee or across multiple subcommittees.

Unaggregated messages (along with metadata) are sent as `SyncCommitteeMessage`s on the `sync_committee_{subnet_id}` topics.

Aggregated sync committee messages are packaged into (signed) `SyncCommitteeContribution` along with proofs and gossiped to the `sync_committee_contribution_and_proof` topic.

#### Transitioning the gossip

With any fork, the fork version, and thus the `ForkDigestValue`, change.
Message types are unique per topic, and so for a smooth transition a node must temporarily subscribe to both the old and new topics.

The topics that are not removed in a fork are updated with a new `ForkDigestValue`. In advance of the fork, a node SHOULD subscribe to the post-fork variants of the topics.

Subscriptions are expected to be well-received, all updated nodes should subscribe as well.
Topic-meshes can be grafted quickly as the nodes are already connected and exchanging gossip control messages.

Messages SHOULD NOT be re-broadcast from one fork to the other.
A node's behavior before the fork and after the fork are as follows:
Pre-fork:
- Peers who propagate messages on the post-fork topics MAY be scored negatively proportionally to time till fork,
  to account for clock discrepancy.
- Messages can be IGNORED on the post-fork topics, with a `MAXIMUM_GOSSIP_CLOCK_DISPARITY` margin.

Post-fork:
- Peers who propagate messages on the pre-fork topics MUST NOT be scored negatively. Lagging IWANT may force them to.
- Messages on pre and post-fork variants of topics share application-level caches.
  E.g. an attestation on the both the old and new topic is ignored like any duplicate.
- Two epochs after the fork, pre-fork topics SHOULD be unsubscribed from. This is well after the configured `seen_ttl`.

#### Encodings

Topics are post-fixed with an encoding. Encodings define how the payload of a gossipsub message is encoded.

- `ssz_snappy` - All objects are SSZ-encoded and then compressed with [Snappy](https://github.com/google/snappy) block compression.
  Example: The beacon aggregate attestation topic string is `/eth2/446a7232/beacon_aggregate_and_proof/ssz_snappy`,
  the fork digest is `446a7232` and the data field of a gossipsub message is an `AggregateAndProof`
  that has been SSZ-encoded and then compressed with Snappy.

Snappy has two formats: "block" and "frames" (streaming).
Gossip messages remain relatively small (100s of bytes to 100s of kilobytes)
so [basic snappy block compression](https://github.com/google/snappy/blob/master/format_description.txt) is used to avoid the additional overhead associated with snappy frames.

Implementations MUST use a single encoding for gossip.
Changing an encoding will require coordination between participating implementations.

### The Req/Resp domain

#### Protocol identification

Each message type is segregated into its own libp2p protocol ID, which is a case-sensitive UTF-8 string of the form:

```
/ProtocolPrefix/MessageName/SchemaVersion/Encoding
```

With:

- `ProtocolPrefix` - messages are grouped into families identified by a shared libp2p protocol name prefix.
  In this case, we use `/eth2/beacon_chain/req`.
- `MessageName` - each request is identified by a name consisting of English alphabet, digits and underscores (`_`).
- `SchemaVersion` - an ordinal version number (e.g. 1, 2, 3…).
  Each schema is versioned to facilitate backward and forward-compatibility when possible.
- `Encoding` - while the schema defines the data types in more abstract terms,
  the encoding strategy describes a specific representation of bytes that will be transmitted over the wire.
  See the [Encodings](#Encoding-strategies) section for further details.

This protocol segregation allows libp2p `multistream-select 1.0` / `multiselect 2.0`
to handle the request type, version, and encoding negotiation before establishing the underlying streams.

#### Req/Resp interaction

We use ONE stream PER request/response interaction.
Streams are closed when the interaction finishes, whether in success or in error.

Request/response messages MUST adhere to the encoding specified in the protocol name and follow this structure (relaxed BNF grammar):

```
request   ::= <encoding-dependent-header> | <encoded-payload>
response  ::= <response_chunk>*
response_chunk  ::= <result> | <context-bytes> | <encoding-dependent-header> | <encoded-payload>
result    ::= “0” | “1” | “2” | [“128” ... ”255”]
```

`<context-bytes>` is empty by default.
On a non-zero `<result>` with `ErrorMessage` payload, the `<context-bytes>` is also empty.
In Altair and later forks, `<context-bytes>` functions as a short meta-data,
defined per req-resp method, and can parametrize the payload decoder.

The encoding-dependent header may carry metadata or assertions such as the encoded payload length, for integrity and attack proofing purposes.
Because req/resp streams are single-use and stream closures implicitly delimit the boundaries, it is not strictly necessary to length-prefix payloads;
however, certain encodings like SSZ do, for added security.

A `response` is formed by zero or more `response_chunk`s.
Responses that consist of a single SSZ-list (such as `BlocksByRange` and `BlocksByRoot`) send each list item as a `response_chunk`.
All other response types (non-Lists) send a single `response_chunk`.

For both `request`s and `response`s, the `encoding-dependent-header` MUST be valid,
and the `encoded-payload` must be valid within the constraints of the `encoding-dependent-header`.
This includes type-specific bounds on payload size for some encoding strategies.
Regardless of these type specific bounds, a global maximum uncompressed byte size of `MAX_CHUNK_SIZE` MUST be applied to all method response chunks.

Clients MUST ensure that lengths are within these bounds; if not, they SHOULD reset the stream immediately.
Clients tracking peer reputation MAY decrement the score of the misbehaving peer under this circumstance.

##### `ForkDigest`-context

Starting with Altair, and in future forks, SSZ type definitions may change.
For this common case, we define the `ForkDigest`-context:

A fixed-width 4 byte `<context-bytes>`, set to the `ForkDigest` matching the chunk:
 `compute_fork_digest(fork_version, genesis_validators_root)`.

##### Requesting side

Once a new stream with the protocol ID for the request type has been negotiated, the full request message SHOULD be sent immediately.
The request MUST be encoded according to the encoding strategy.

The requester MUST close the write side of the stream once it finishes writing the request message.
At this point, the stream will be half-closed.

The requester MUST wait a maximum of `TTFB_TIMEOUT` for the first response byte to arrive (time to first byte—or TTFB—timeout).
On that happening, the requester allows a further `RESP_TIMEOUT` for each subsequent `response_chunk` received.

If any of these timeouts fire, the requester SHOULD reset the stream and deem the req/resp operation to have failed.

A requester SHOULD read from the stream until either:
1. An error result is received in one of the chunks (the error payload MAY be read before stopping).
2. The responder closes the stream.
3. Any part of the `response_chunk` fails validation.
4. The maximum number of requested chunks are read.

For requests consisting of a single valid `response_chunk`,
the requester SHOULD read the chunk fully, as defined by the `encoding-dependent-header`, before closing the stream.

##### Responding side

Once a new stream with the protocol ID for the request type has been negotiated,
the responder SHOULD process the incoming request and MUST validate it before processing it.
Request processing and validation MUST be done according to the encoding strategy, until EOF (denoting stream half-closure by the requester).

The responder MUST:

1. Use the encoding strategy to read the optional header.
2. If there are any length assertions for length `N`, it should read exactly `N` bytes from the stream, at which point an EOF should arise (no more bytes).
  Should this not be the case, it should be treated as a failure.
3. Deserialize the expected type, and process the request.
4. Write the response which may consist of zero or more `response_chunk`s (result, optional header, payload).
5. Close their write side of the stream. At this point, the stream will be fully closed.

If steps (1), (2), or (3) fail due to invalid, malformed, or inconsistent data, the responder MUST respond in error.
Clients tracking peer reputation MAY record such failures, as well as unexpected events, e.g. early stream resets.

The entire request should be read in no more than `RESP_TIMEOUT`.
Upon a timeout, the responder SHOULD reset the stream.

The responder SHOULD send a `response_chunk` promptly.
Chunks start with a **single-byte** response code which determines the contents of the `response_chunk` (`result` particle in the BNF grammar above).
For multiple chunks, only the last chunk is allowed to have a non-zero error code (i.e. The chunk stream is terminated once an error occurs).

The response code can have one of the following values, encoded as a single unsigned byte:

-  0: **Success** -- a normal response follows, with contents matching the expected message schema and encoding specified in the request.
-  1: **InvalidRequest** -- the contents of the request are semantically invalid, or the payload is malformed, or could not be understood.
  The response payload adheres to the `ErrorMessage` schema (described below).
-  2: **ServerError** -- the responder encountered an error while processing the request.
  The response payload adheres to the `ErrorMessage` schema (described below).
-  3: **ResourceUnavailable** -- the responder does not have requested resource.
  The response payload adheres to the `ErrorMessage` schema (described below).
  *Note*: This response code is only valid as a response where specified.

Clients MAY use response codes above `128` to indicate alternative, erroneous request-specific responses.

The range `[4, 127]` is RESERVED for future usages, and should be treated as error if not recognized expressly.

The `ErrorMessage` schema is:

```
(
  error_message: List[byte, 256]
)
```

*Note*: By convention, the `error_message` is a sequence of bytes that MAY be interpreted as a UTF-8 string (for debugging purposes).
Clients MUST treat as valid any byte sequences.

#### Encoding strategies

The token of the negotiated protocol ID specifies the type of encoding to be used for the req/resp interaction.
Only one value is possible at this time:

-  `ssz_snappy`: The contents are first [SSZ-encoded](../../ssz/simple-serialize.md)
  and then compressed with [Snappy](https://github.com/google/snappy) frames compression.
  For objects containing a single field, only the field is SSZ-encoded not a container with a single field.
  For example, the `BeaconBlocksByRoot` request is an SSZ-encoded list of `Root`'s.
  This encoding type MUST be supported by all clients.

##### SSZ-snappy encoding strategy

The [SimpleSerialize (SSZ) specification](../../ssz/simple-serialize.md) outlines how objects are SSZ-encoded.

To achieve snappy encoding on top of SSZ, we feed the serialized form of the object to the Snappy compressor on encoding.
The inverse happens on decoding.

Snappy has two formats: "block" and "frames" (streaming).
To support large requests and response chunks, snappy-framing is used.

Since snappy frame contents [have a maximum size of `65536` bytes](https://github.com/google/snappy/blob/master/framing_format.txt#L104)
and frame headers are just `identifier (1) + checksum (4)` bytes, the expected buffering of a single frame is acceptable.

**Encoding-dependent header:** Req/Resp protocols using the `ssz_snappy` encoding strategy MUST encode the length of the raw SSZ bytes,
encoded as an unsigned [protobuf varint](https://developers.google.com/protocol-buffers/docs/encoding#varints).

*Writing*: By first computing and writing the SSZ byte length, the SSZ encoder can then directly write the chunk contents to the stream.
When Snappy is applied, it can be passed through a buffered Snappy writer to compress frame by frame.

*Reading*: After reading the expected SSZ byte length, the SSZ decoder can directly read the contents from the stream.
When snappy is applied, it can be passed through a buffered Snappy reader to decompress frame by frame.

Before reading the payload, the header MUST be validated:
- The unsigned protobuf varint used for the length-prefix MUST not be longer than 10 bytes, which is sufficient for any `uint64`.
- The length-prefix is within the expected [size bounds derived from the payload SSZ type](#what-are-ssz-type-size-bounds).

After reading a valid header, the payload MAY be read, while maintaining the size constraints from the header.

A reader SHOULD NOT read more than `max_encoded_len(n)` bytes after reading the SSZ length-prefix `n` from the header.
- For `ssz_snappy` this is: `32 + n + n // 6`.
  This is considered the [worst-case compression result](https://github.com/google/snappy/blob/537f4ad6240e586970fe554614542e9717df7902/snappy.cc#L98) by Snappy.

A reader SHOULD consider the following cases as invalid input:
- Any remaining bytes, after having read the `n` SSZ bytes. An EOF is expected if more bytes are read than required.
- An early EOF, before fully reading the declared length-prefix worth of SSZ bytes.

In case of an invalid input (header or payload), a reader MUST:
- From requests: send back an error message, response code `InvalidRequest`. The request itself is ignored.
- From responses: ignore the response, the response MUST be considered bad server behavior.

All messages that contain only a single field MUST be encoded directly as the type of that field and MUST NOT be encoded as an SSZ container.

Responses that are SSZ-lists (for example `List[SignedBeaconBlock, ...]`) send their
constituents individually as `response_chunk`s. For example, the
`List[SignedBeaconBlock, ...]` response type sends zero or more `response_chunk`s.
Each _successful_ `response_chunk` contains a single `SignedBeaconBlock` payload.

#### Messages

##### Status

**Protocol ID:** ``/eth2/beacon_chain/req/status/1/``

Request, Response Content:
```
(
  fork_digest: ForkDigest
  finalized_root: Root
  finalized_epoch: Epoch
  head_root: Root
  head_slot: Slot
)
```
The fields are, as seen by the client at the time of sending the message:

- `fork_digest`: The node's `ForkDigest` (`compute_fork_digest(current_fork_version, genesis_validators_root)`) where
    - `current_fork_version` is the fork version at the node's current epoch defined by the wall-clock time
      (not necessarily the epoch to which the node is sync)
    - `genesis_validators_root` is the static `Root` found in `state.genesis_validators_root`
- `finalized_root`: `state.finalized_checkpoint.root` for the state corresponding to the head block
  (Note this defaults to `Root(b'\x00' * 32)` for the genesis finalized checkpoint).
- `finalized_epoch`: `state.finalized_checkpoint.epoch` for the state corresponding to the head block.
- `head_root`: The `hash_tree_root` root of the current head block (`BeaconBlock`).
- `head_slot`: The slot of the block corresponding to the `head_root`.

The dialing client MUST send a `Status` request upon connection.

The request/response MUST be encoded as an SSZ-container.

The response MUST consist of a single `response_chunk`.

Clients SHOULD immediately disconnect from one another following the handshake above under the following conditions:

1. If `fork_digest` does not match the node's local `fork_digest`, since the client’s chain is on another fork.
2. If the (`finalized_root`, `finalized_epoch`) shared by the peer is not in the client's chain at the expected epoch.
  For example, if Peer 1 sends (root, epoch) of (A, 5) and Peer 2 sends (B, 3) but Peer 1 has root C at epoch 3,
  then Peer 1 would disconnect because it knows that their chains are irreparably disjoint.

Once the handshake completes, the client with the lower `finalized_epoch` or `head_slot` (if the clients have equal `finalized_epoch`s)
SHOULD request beacon blocks from its counterparty via the `BeaconBlocksByRange` request.

*Note*: Under abnormal network condition or after some rounds of `BeaconBlocksByRange` requests,
the client might need to send `Status` request again to learn if the peer has a higher head.
Implementers are free to implement such behavior in their own way.

##### Goodbye

**Protocol ID:** ``/eth2/beacon_chain/req/goodbye/1/``

Request, Response Content:
```
(
  uint64
)
```
Client MAY send goodbye messages upon disconnection. The reason field MAY be one of the following values:

- 1: Client shut down.
- 2: Irrelevant network.
- 3: Fault/error.

Clients MAY use reason codes above `128` to indicate alternative, erroneous request-specific responses.

The range `[4, 127]` is RESERVED for future usage.

The request/response MUST be encoded as a single SSZ-field.

The response MUST consist of a single `response_chunk`.

##### BeaconBlocksByRange

**Protocol ID:** `/eth2/beacon_chain/req/beacon_blocks_by_range/1/`

Request Content:
```
(
  start_slot: Slot
  count: uint64
  step: uint64 # Deprecated, must be set to 1
)
```

Response Content:
```
(
  List[SignedBeaconBlock, MAX_REQUEST_BLOCKS]
)
```

Requests beacon blocks in the slot range `[start_slot, start_slot + count)`, leading up to the current head block as selected by fork choice.
For example, requesting blocks starting at `start_slot=2` and `count=4` would return the blocks at slots `[2, 3, 4, 5]`.
In cases where a slot is empty for a given slot number, no block is returned.
For example, if slot 4 were empty in the previous example, the returned array would contain `[2, 3, 5]`.

`step` is deprecated and must be set to 1. Clients may respond with a single block if a larger step is returned during the deprecation transition period.

`/eth2/beacon_chain/req/beacon_blocks_by_range/1/` is deprecated. Clients MAY respond with an empty list during the deprecation transition period.

`BeaconBlocksByRange` is primarily used to sync historical blocks.

The request MUST be encoded as an SSZ-container.

The response MUST consist of zero or more `response_chunk`.
Each _successful_ `response_chunk` MUST contain a single `SignedBeaconBlock` payload.

Clients MUST keep a record of signed blocks seen on the epoch range
`[max(GENESIS_EPOCH, current_epoch - MIN_EPOCHS_FOR_BLOCK_REQUESTS), current_epoch]`
where `current_epoch` is defined by the current wall-clock time,
and clients MUST support serving requests of blocks on this range.

Peers that are unable to reply to block requests within the `MIN_EPOCHS_FOR_BLOCK_REQUESTS`
epoch range SHOULD respond with error code `3: ResourceUnavailable`.
Such peers that are unable to successfully reply to this range of requests MAY get descored
or disconnected at any time.

*Note*: The above requirement implies that nodes that start from a recent weak subjectivity checkpoint
MUST backfill the local block database to at least epoch `current_epoch - MIN_EPOCHS_FOR_BLOCK_REQUESTS`
to be fully compliant with `BlocksByRange` requests. To safely perform such a
backfill of blocks to the recent state, the node MUST validate both (1) the
proposer signatures and (2) that the blocks form a valid chain up to the most
recent block referenced in the weak subjectivity state.

*Note*: Although clients that bootstrap from a weak subjectivity checkpoint can begin
participating in the networking immediately, other peers MAY
disconnect and/or temporarily ban such an un-synced or semi-synced client.

Clients MUST respond with at least the first block that exists in the range, if they have it,
and no more than `MAX_REQUEST_BLOCKS` blocks.

The following blocks, where they exist, MUST be sent in consecutive order.

Clients MAY limit the number of blocks in the response.

The response MUST contain no more than `count` blocks.

Clients MUST respond with blocks from their view of the current fork choice
-- that is, blocks from the single chain defined by the current head.
Of note, blocks from slots before the finalization MUST lead to the finalized block reported in the `Status` handshake.

Clients MUST respond with blocks that are consistent from a single chain within the context of the request.
This applies to any `step` value.
In particular when `step == 1`, each `parent_root` MUST match the `hash_tree_root` of the preceding block.

After the initial block, clients MAY stop in the process of responding
if their fork choice changes the view of the chain in the context of the request.

##### BeaconBlocksByRange v2

**Protocol ID:** `/eth2/beacon_chain/req/beacon_blocks_by_range/2/`

Request and Response remain unchanged. A `ForkDigest`-context is used to select the fork namespace of the Response type.

Per `context = compute_fork_digest(fork_version, genesis_validators_root)`:

[0]: # (eth2spec: skip)

| `fork_version`           | Chunk SSZ type             |
| ------------------------ | -------------------------- |
| `GENESIS_FORK_VERSION`   | `phase0.SignedBeaconBlock` |
| `ALTAIR_FORK_VERSION`    | `altair.SignedBeaconBlock` |
| `BELLATRIX_FORK_VERSION` | `bellatrix.SignedBeaconBlock` |
| `CAPELLA_FORK_VERSION`   | `capella.SignedBeaconBlock` |

##### BeaconBlocksByRoot

**Protocol ID:** `/eth2/beacon_chain/req/beacon_blocks_by_root/1/`

Request Content:

```
(
  List[Root, MAX_REQUEST_BLOCKS]
)
```

Response Content:

```
(
  List[SignedBeaconBlock, MAX_REQUEST_BLOCKS]
)
```

Requests blocks by block root (= `hash_tree_root(SignedBeaconBlock.message)`).
The response is a list of `SignedBeaconBlock` whose length is less than or equal to the number of requested blocks.
It may be less in the case that the responding peer is missing blocks.

No more than `MAX_REQUEST_BLOCKS` may be requested at a time.

`BeaconBlocksByRoot` is primarily used to recover recent blocks (e.g. when receiving a block or attestation whose parent is unknown).

The request MUST be encoded as an SSZ-field.

The response MUST consist of zero or more `response_chunk`.
Each _successful_ `response_chunk` MUST contain a single `SignedBeaconBlock` payload.

Clients MUST support requesting blocks since the latest finalized epoch.

Clients MUST respond with at least one block, if they have it.
Clients MAY limit the number of blocks in the response.

`/eth2/beacon_chain/req/beacon_blocks_by_root/1/` is deprecated. Clients MAY respond with an empty list during the deprecation transition period.

##### BeaconBlocksByRoot v2

**Protocol ID:** `/eth2/beacon_chain/req/beacon_blocks_by_root/2/`

Request and Response remain unchanged. A `ForkDigest`-context is used to select the fork namespace of the Response type.

Per `context = compute_fork_digest(fork_version, genesis_validators_root)`:

[1]: # (eth2spec: skip)

| `fork_version`           | Chunk SSZ type             |
| ------------------------ | -------------------------- |
| `GENESIS_FORK_VERSION`   | `phase0.SignedBeaconBlock` |
| `ALTAIR_FORK_VERSION`    | `altair.SignedBeaconBlock` |
| `BELLATRIX_FORK_VERSION` | `bellatrix.SignedBeaconBlock` |
| `CAPELLA_FORK_VERSION`   | `capella.SignedBeaconBlock` |

##### Ping

**Protocol ID:** `/eth2/beacon_chain/req/ping/1/`

Request Content:

```
(
  uint64
)
```

Response Content:

```
(
  uint64
)
```

Sent intermittently, the `Ping` protocol checks liveness of connected peers.
Peers request and respond with their local metadata sequence number (`MetaData.seq_number`).

If the peer does not respond to the `Ping` request, the client MAY disconnect from the peer.

A client can then determine if their local record of a peer's MetaData is up to date
and MAY request an updated version via the `MetaData` RPC method if not.

The request MUST be encoded as an SSZ-field.

The response MUST consist of a single `response_chunk`.

##### GetMetaData

**Protocol ID:** `/eth2/beacon_chain/req/metadata/1/`

No Request Content.

Response Content:

```
(
  MetaData
)
```

Requests the MetaData of a peer.
The request opens and negotiates the stream without sending any request content.
Once established the receiving peer responds with
it's local most up-to-date MetaData.

The response MUST be encoded as an SSZ-container.

The response MUST consist of a single `response_chunk`.

##### GetMetaData v2

**Protocol ID:** `/eth2/beacon_chain/req/metadata/2/`

No Request Content.

Response Content:

```
(
  MetaData
)
```

Requests the MetaData of a peer, using the new `MetaData` definition given above
that is extended from phase 0 in Altair. Other conditions for the `GetMetaData`
protocol are unchanged from the phase 0 p2p networking document.

#### Transitioning from v1 to v2

In advance of the fork, implementations can opt in to both run the v1 and v2 for a smooth transition.
This is non-breaking, and is recommended as soon as the fork specification is stable.

The v1 variants will be deprecated, and implementations should use v2 when available
(as negotiated with peers via LibP2P multistream-select).

The v1 method MAY be unregistered at the fork boundary.
In the event of a request on v1 for an Altair specific payload,
the responder MUST return the **InvalidRequest** response code.

### The discovery domain: discv5

Discovery Version 5 ([discv5](https://github.com/ethereum/devp2p/blob/master/discv5/discv5.md)) (Protocol version v5.1) is used for peer discovery.

`discv5` is a standalone protocol, running on UDP on a dedicated port, meant for peer discovery only.
`discv5` supports self-certified, flexible peer records (ENRs) and topic-based advertisement, both of which are (or will be) requirements in this context.

#### Integration into libp2p stacks

`discv5` SHOULD be integrated into the client’s libp2p stack by implementing an adaptor
to make it conform to the [service discovery](https://github.com/libp2p/go-libp2p-core/blob/master/discovery/discovery.go)
and [peer routing](https://github.com/libp2p/go-libp2p-core/blob/master/routing/routing.go#L36-L44) abstractions and interfaces (go-libp2p links provided).

Inputs to operations include peer IDs (when locating a specific peer) or capabilities (when searching for peers with a specific capability),
and the outputs will be multiaddrs converted from the ENR records returned by the discv5 backend.

This integration enables the libp2p stack to subsequently form connections and streams with discovered peers.

#### ENR structure

The Ethereum Node Record (ENR) for an Ethereum consensus client MUST contain the following entries
(exclusive of the sequence number and signature, which MUST be present in an ENR):

-  The compressed secp256k1 publickey, 33 bytes (`secp256k1` field).

The ENR MAY contain the following entries:

-  An IPv4 address (`ip` field) and/or IPv6 address (`ip6` field).
-  A TCP port (`tcp` field) representing the local libp2p listening port.
-  A UDP port (`udp` field) representing the local discv5 listening port.

Specifications of these parameters can be found in the [ENR Specification](http://eips.ethereum.org/EIPS/eip-778).

##### Attestation subnet bitfield

The ENR `attnets` entry signifies the attestation subnet bitfield with the following form
to more easily discover peers participating in particular attestation gossip subnets.

| Key          | Value                                            |
|:-------------|:-------------------------------------------------|
| `attnets`    | SSZ `Bitvector[ATTESTATION_SUBNET_COUNT]`        |

If a node's `MetaData.attnets` has any non-zero bit, the ENR MUST include the `attnets` entry with the same value as `MetaData.attnets`.

If a node's `MetaData.attnets` is composed of all zeros, the ENR MAY optionally include the `attnets` entry or leave it out entirely.

##### `syncnets` bitfield

An additional bitfield is added to the ENR under the key `syncnets` to facilitate sync committee subnet discovery.
The length of this bitfield is `SYNC_COMMITTEE_SUBNET_COUNT` where each bit corresponds to a distinct `subnet_id` for a specific sync committee subnet.
The `i`th bit is set in this bitfield if the validator is currently subscribed to the `sync_committee_{i}` topic.

See the [validator document](./validator.md#sync-committee-subnet-stability) for further details on how the new bits are used.

##### `eth2` field

ENRs MUST carry a generic `eth2` key with an 16-byte value of the node's current fork digest, next fork version,
and next fork epoch to ensure connections are made with peers on the intended Ethereum network.

| Key          | Value               |
|:-------------|:--------------------|
| `eth2`       | SSZ `ENRForkID`        |

Specifically, the value of the `eth2` key MUST be the following SSZ encoded object (`ENRForkID`)

```
(
    fork_digest: ForkDigest
    next_fork_version: Version
    next_fork_epoch: Epoch
)
```

where the fields of `ENRForkID` are defined as

* `fork_digest` is `compute_fork_digest(current_fork_version, genesis_validators_root)` where
    * `current_fork_version` is the fork version at the node's current epoch defined by the wall-clock time
      (not necessarily the epoch to which the node is sync)
    * `genesis_validators_root` is the static `Root` found in `state.genesis_validators_root`
* `next_fork_version` is the fork version corresponding to the next planned hard fork at a future epoch.
  If no future fork is planned, set `next_fork_version = current_fork_version` to signal this fact
* `next_fork_epoch` is the epoch at which the next fork is planned and the `current_fork_version` will be updated.
  If no future fork is planned, set `next_fork_epoch = FAR_FUTURE_EPOCH` to signal this fact

*Note*: `fork_digest` is composed of values that are not known until the genesis block/state are available.
Due to this, clients SHOULD NOT form ENRs and begin peer discovery until genesis values are known.
One notable exception to this rule is the distribution of bootnode ENRs prior to genesis.
In this case, bootnode ENRs SHOULD be initially distributed with `eth2` field set as
`ENRForkID(fork_digest=compute_fork_digest(GENESIS_FORK_VERSION, b'\x00'*32), next_fork_version=GENESIS_FORK_VERSION, next_fork_epoch=FAR_FUTURE_EPOCH)`.
After genesis values are known, the bootnodes SHOULD update ENRs to participate in normal discovery operations.

Clients SHOULD connect to peers with `fork_digest`, `next_fork_version`, and `next_fork_epoch` that match local values.

Clients MAY connect to peers with the same `fork_digest` but a different `next_fork_version`/`next_fork_epoch`.
Unless `ENRForkID` is manually updated to matching prior to the earlier `next_fork_epoch` of the two clients,
these connecting clients will be unable to successfully interact starting at the earlier `next_fork_epoch`.

### Attestation subnet subscription

Because Phase 0 does not have shards and thus does not have Shard Committees, there is no stable backbone to the attestation subnets (`beacon_attestation_{subnet_id}`). To provide this stability, each beacon node should:

* Remain subscribed to `SUBNETS_PER_NODE` for `EPOCHS_PER_SUBNET_SUBSCRIPTION` epochs.
* Maintain advertisement of the selected subnets in their node's ENR `attnets` entry by setting the selected `subnet_id` bits to `True` (e.g. `ENR["attnets"][subnet_id] = True`) for all persistent attestation subnets.
* Select these subnets based on their node-id as specified by the following `compute_subscribed_subnets(node_id, epoch)` function.

```python
def compute_subscribed_subnet(node_id: NodeID, epoch: Epoch, index: int) -> SubnetID:
    node_id_prefix = node_id >> (NODE_ID_BITS - ATTESTATION_SUBNET_PREFIX_BITS)
    node_offset = node_id % EPOCHS_PER_SUBNET_SUBSCRIPTION
    permutation_seed = hash(uint_to_bytes(uint64((epoch + node_offset) // EPOCHS_PER_SUBNET_SUBSCRIPTION)))
    permutated_prefix = compute_shuffled_index(
        node_id_prefix,
        1 << ATTESTATION_SUBNET_PREFIX_BITS,
        permutation_seed,
    )
    return SubnetID((permutated_prefix + index) % ATTESTATION_SUBNET_COUNT)
```

```python
def compute_subscribed_subnets(node_id: NodeID, epoch: Epoch) -> Sequence[SubnetID]:
    return [compute_subscribed_subnet(node_id, epoch, index) for index in range(SUBNETS_PER_NODE)]
```

*Note*: When preparing for a hard fork, a node must select and subscribe to subnets of the future fork versioning at least `EPOCHS_PER_SUBNET_SUBSCRIPTION` epochs in advance of the fork. These new subnets for the fork are maintained in addition to those for the current fork until the fork occurs. After the fork occurs, let the subnets from the previous fork reach the end of life with no replacements.
