# Architecture of the consensus node

## Processes summary

This is our complete supervision tree.

```mermaid
graph LR
Application[Application <br> <:one_for_one>]
BeaconNode[BeaconNode <br> <:one_for_all>]
ValidatorManager[ValidatorManager <br> <:one_for_one>]
Telemetry[Telemetry <br> <:one_for_one>]

Application --> Telemetry
Application --> DB
Application --> Blocks
Application --> BlockStates
Application --> BeaconNode
Application --> BeaconApi.Endpoint

subgraph Basic infrastructure
    DB
    BeaconApi.Endpoint
    Telemetry
    :telemetry_poller
    TelemetryMetricsPrometheus
end

subgraph Caches
    Blocks
    BlockStates
end

BeaconNode -->|listen_addr, <br>enable_discovery, <br> discovery_addr, <br>bootnodes| P2P.Libp2pPort
BeaconNode --> SyncBlocks
BeaconNode -->|slot, head_root| ValidatorManager
ValidatorManager --> ValidatorN

Telemetry --> :telemetry_poller
Telemetry --> TelemetryMetricsPrometheus
```

Each box is a process. If it has children, it's a supervisor, with it's restart strategy clarified. 

If it's a leaf in the tree, it's a GenServer, task, or other non-supervisor process. The tags in the edges/arrows are the init args passed on children init (start or restart after crash).

## P2P Events

This section contains sequence diagrams representing the interaction of processes through time in response to a stimulus. The main entry point for new events is through gossip and request-response protocols, which is how nodes communicates between each other.

Request-response is a simple protocol where client request for specific data such as old blocks that they may be missing or other clients metadata.

Gossip allows clients to subscribe to different topics (hence the name "gossipsub") they are interested in, and get updates for them. This is how a node receives new blocks or attestations from their peers.

We use the `go-libp2p` library for the networking primitives, which is an implementation of the `libp2p` networking stack. We use ports to communicate with a go application and Broadway to process notifications. This port has a GenServer owner called `Libp2pPort`.

## Gossipsub

### Subscribing

At the beginning of the application we subscribe a series of handler processes that will react to new gossipsub events:

- `Gossip.BeaconBlock` will handle topic `/eth2/<context>/beacon_block/ssz_snappy`.
- `Gossip.BlobSideCar` will subscribe to all blob subnet topics. They're names are of the form `/eth2/<context>/blob_sidecar_<subnet_index>`.
- `Gossip.OperationsCollector` will subscribe to operations `beacon_aggregate_and_proof` (attestations), `voluntary_exit`, `proposer_slashing`, `attester_slashing`, `bls_to_execution_change`.

This is the process of subscribing, taking the operations collector as an example:

```mermaid
sequenceDiagram
participant sync as SyncBlocks
participant ops as OperationsCollector
participant p2p as Libp2pPort <br> (GenServer)
participant port as Go Libp2p<br>(Port)

ops ->>+ ops: init()

loop
    ops ->> p2p: join_topic
    p2p ->> port: join_command

end
deactivate ops

sync ->>+ ops: start()

loop
    ops ->> p2p: subscribe_to_topic
    p2p ->> port: subscribe_command <br> from: operations_collector_pid
end
deactivate ops

port ->>+ p2p: gossipsub_message <br> handler: operations_collector_pid
p2p ->> ops: {:gossipsub, topic, message}
deactivate p2p
activate ops
ops ->>ops: handle_msg(message)
deactivate ops
```

Joining a topic allows the node to get the messages and participate in gossip for that topic. Subscribing means that the node will actually read the contents of those messages.

We delay the subscription until the sync is finished to guarantee that we're at a point where we can process the messages that we receive.

This will send the following message to the go libp2p app:

```elixir
%Command{
    from: self() |> :erlant.term_to_binary(),
    c: {:subscribe, %SubscribeToTopic{name: topic_name}}
}
```

`self` here is the caller, which is `OperationsCollector`'s pid. The go side will save that binary representation of the pid and attach it to gossip messages that arrive for that topic. That is, the messages that will be notified to `Libp2pPort` will be of the form:

```elixir
%Gossipsub{
    handler: operations_collector_pid,
    message: message,
    msg_id: id
}
```

The operations collector then handles that message on `handle_info`, which means it deserializes and decompresses each message and then call specific handlers for that topic.

### Receiving an attestation

This is the intended way to process attestations in the current architecture, although the fork choice call is disabled and only attestations in blocks are being processed.

```mermaid
sequenceDiagram
    participant p2p as Libp2pPort
    participant ops as OperationsCollector
    participant fc as ForkChoice

    p2p ->>+ ops: {:gossipsub, "beacon_aggregate_and_proof", att}
    ops ->> ops: Decompress and deserialize message
    ops ->>+ fc: on_attestation() <br> (disabled)
    fc ->>- fc: Handlers.on_attestation(store, attestation, false)
    ops ->>- ops: handle_msg({:attestation, aggregate}, state)


```

When receiving an attestation, the ForkChoice GenServer takes the current store object and modifies it using the [`on_attestation`](https://eth2book.info/capella/annotated-spec/#on_attestation) handler. It validates it and updates the fork tree weights and target checkpoints. The attestation is only processed if this attestation is the latest message by that validator. If there's a newer one, it should be discarded.

The most relevant piece of the spec here is the [get_weight](https://eth2book.info/capella/annotated-spec/#get_weight) function, which is the core of the fork-choice algorithm. In the specs, this function is called on demand, when calling [get_head](https://eth2book.info/capella/annotated-spec/#get_head), works with the store's values, and recalculates them each time. In our case, we cache the weights and the head root each time we add a block or attestation, so we don't need to do the same calculations again.

**To do**: we should probably save the latest messages in persistent storage as well so that if the node crashes we can recover the tree weights.

### Receiving a block

A block is first received and sent to the `PendingBlocks` GenServer, which checks if the block has everything needed or if it's duplicated before letting it be processed.

```mermaid
sequenceDiagram
    participant port as Libp2pPort
    participant block as BeaconBlock
    participant pending as PendingBlocks

    activate block
    port ->> block: {:gossipsub, {topic, id, message}}
    block ->> block: Decompress and deserialize message
    block ->> port: validate_message(id, :accept)
    block ->> pending: {:add_block, SignedBeaconBlock}
    deactivate block

```

However, the block isn't processed immediately. Once every 500ms, `PendingBlocks` checks if there are blocks that should be processed and does so.

```mermaid
sequenceDiagram
    participant pending as PendingBlocks
    participant FC as Fork-choice store
    participant rec as recompute_head <br> (async task)
    participant StoreDB
    participant subs as OperationsCollector <br> Validators <br> ExecutionClient <br> BeaconChain

    pending ->> pending: :process_blocks
    activate pending
    loop
        pending ->> pending: check which blocks are pending <br> check parent is downloaded and processed
        pending ->>+ FC: {:on_block, block_root, signed_block, from}
        deactivate pending
    end

    FC ->> FC: process_block
    FC ->>+ rec: recompute_head(store)
    FC ->> FC: prune_old_states
    FC ->> pending: {:block_processed, block_root, true}
    deactivate FC

    rec ->> StoreDB: pruned_store
    rec ->> rec: Handlers.get_head()
    rec ->> subs: notify_new_block

```

For the happy path, shown above, fork choice store calculates the state transition, and notifies the pending blocks GenServer that the block was correctly processed, so it can mark it as such.

Asynchronously, a new task is started to recompute the new head, as this takes a significant amount of time. When the head is recomputed, multiple processes are notified.

## Request-Response

Request-response is an on-demand protocol where a node asks for information directly to a peer and expects a response. This may be to request metadata that corresponds to that peer for discovery purposes, or to request information from the past that will not appear on when listening to gossip (useful for checkpoint sync).

It's implemented in the following way:

```mermaid
sequenceDiagram

participant req as Requesting Process
participant p2p as Libp2pPort
participant gomain as go libp2p main
participant goreq as request goroutine

req ->> req: send_request(peer_id, protocol_id, message)
req ->> p2p: send_protobuf(from: self())
activate p2p
p2p ->> gomain: %Command{}
deactivate p2p
req ->>+ req: receive_response()

gomain ->> gomain: handle_command()
gomain ->>+ goreq: go sendAsyncRequest()
goreq ->>- p2p: SendNotification(%Result{from, response, err})

p2p ->>p2p: handle_notification(%Result{from: from})
p2p ->> req: {:response, result}
deactivate req
```

Explained, a process that wants to request something from Libp2pPort sends a request with its own pid, which is then included in the Command payload. The request is handled asynchronously in the go side, and eventually, the pid is included in the response, and sent back to LibP2PPort, who now knows to which process it needs to be dispatched.

The specific kind of command (a request) is specified, but there's nothing identifying this is a response vs any other kind of result, or the specific kind of response (e.g. a block download vs a blob download). Currently the only way this is handled differentially is because the pid is waiting for a specific kind of response and for nothing else at a time.

## Validators

Validators are separate processes. They react to:

- Clock ticks: this allows them to compute their duties for different sections of the slot:
  - First third: producing a block and sending it to the general gossip channel.
  - Second third: Attesting for a block and sending it to a subnet.
  - Last third: aggregating attestations from a subnet and sending them over the general gossip network.
- Fork choice results (head updates): these are needed by the validators to build the blocks accordingly when proposing, as they will get the head state, create a block on top of it and apply a state transition.

### Attester duty calculation

Duties are calculated by the `LambdaEthereumConsensus.Validator.Duties` module. This should be done once every epoch. In the current implementation it's done when:

- A new head appears for the same current slot.
- There's an epoch change.

A validator must attest once per epoch, in one committee. There are multiple committees per slot. In the current design, all attestation committees are calculated for every slot of the epoch, and then the one containing the validator is returned, thus obtaining the slot and committee index within the slot for that validator.

There's some room for optimizations here:

- We should calculate the committees only once for all validators.
- We should not calculate the full committees, we should only shuffle the validators that we are handling to know in which slot and committee they are in an epoch.

### Proposing duties

There's only one block proposer per slot and there are about 1 million validators in mainnet. That means that a block will be chosen approximately once every 12 million seconds (a slot is 12 seconds), which is roughly 4 months and 19 days.

Each proposer index is calculated for the whole epoch, using the hash of the epoch's randao mix + metadata as a seed.

This too could be calculated only once for all validators, but it's not as big as a task compared to calculating all committees.

### Building blocks

When proposing a block, the "block builder" is used.

In the previous block to proposing, the payload build starts:

- The head block and state are fetched from the db.
- The block metadata is obtained from the blocks execution payload.
- Slots are processed if necessary.
- The execution client is notified of the fork choice update.

In the proposing slot:

- The process of getting the pre-state, processing slots, etc. is repeated (this could be optimized).
- The execution payload and blob bundle are requested directly to the execution client for the corresponding payload_id.
- The operations (slashings, attestations voluntary exits) that were collected from gossip are added to the block.
- The deposits and eth1_vote are fetched from `ExecutionChain`.
- The block is signed.

## Execution Chain

The consensus node needs to communicate with the execution client for three different reasons:

- Fork choice updates: the execution clients needs notifications when the head is updated, and payloads need validation. For these goals, `engineAPI` is used.
- Deposit contract tracking: accounts that wish to become validators need to deposit 32ETH in the deposit contract. This happens in the execution chain, but the information needs to arrive to consensus for the validator set to be updated.
- Eth 1 votes: consensus nodes agree on a summary of the execution state and a voting mechanism is built for this.

Let's go to this communication sections one by one.

### Engine API: fork choice updates

The consensus node does not live in isolation. It communicates to the execution client. We implemented, in the `ExecutionClient` module, the following primitives:

- `notify_forkchoice_updated(fork_choice_state)`: first message sent to the execution client right after exchanging capabilities. It returns if the client is syncing or valid.
- `notify_forkchoice_updated(fork_choice_state, payload_attributes)`: sent to update the fork choice state in the execution client (finalized and head payload hash). This starts the execution payload build process. Returns a `payload_id` that will be used at block building time to get the actual execution payload. It's sent in the slot prior to proposing. It might return a null id if the execution client is still syncing.
- `get_payload(payload_id)`: returns an `{ExecutionPayload.t(), BlobsBundle.t()}` tuple that started building when `notify_forkchoice_updated` was called with payload attributes.
- `notify_new_payload(execution_payload, versioned_hashes, parent_beacon_block_root)`: when the execution client gets a new block, it needs to check if the execution payload is valid. This method is used to send that payload for verification. It may return valid, invalid, or syncing, in the case where the execution client is not yet synced.

### Deposit contract

Each time there's a deposit, a log is included in the execution block that can be read by the consensus layer using the `get_deposit_logs(range)` function for this.

Each deposit has the following form:

```elixir
%DepositData {
    # BLS Credentials publicly identifying the validator.
    pubkey: Types.bls_pubkey(),
    # Public address where the stake rewards will be sent.
    withdrawal_credentials: Types.bytes32(),
    # Amount of eth deposited.
    amount: Types.gwei(),
    # Signature over the other fields.
    signature: Types.bls_signature()
}
```

These deposits are aggregated into a merkle trie where each deposit is a leaf. After aggregation we can obtain:

- A `deposit_root`: root of the merkle trie.
- A `deposit_count`: the amount of deposits that were processed in the execution layer.

This aggregation structure is useful to send snapshots cheaply, when performing checkpoint sync. See [EIP-4881](https://eips.ethereum.org/EIPS/eip-4881). It can also be used to send cheap merkle proofs that show a deposit is part of the current deposit set.

### Eth 1 voting

Validators have a summarized view of the execution chain, stored in a struct called `Eth1Data`:

```elixir
%Eth1Data{
    deposit_root: Types.root(),
    deposit_count: Types.uint64(),
    block_hash: Types.hash32()
}
```

This is the full process of how this data is included in the consensus state:

- There's a voting period each 64 epochs. That is, 2048 slots, almost 7 hours. There's a period change when `rem(next_epoch, epochs_per_eth1_voting_period) == 0`.
- Each proposer include their view of the chain (`Eth1Data`) in the block they propose (`block.body.eth1_data`). They obtain this data from their own execution client. This is sometimes called their "eth 1 vote".
- When state transition is performed using that block, the vote is included in the `beacon_state.eth1_data_votes` array, which contains the votes for the whole voting period. If a single `eth1_data_vote` is present in more than half of the period slots, then it's now considered the current `eth1_data`, which means it's assigned as `beacon_state.eth1_data` in that state transition.
- After an eth1 data vote period finishes, the `beacon_state.eth1_data_votes` are reset (the list is assigned as empty), regardless of there being a winner (new eth 1 data after the period) or not.

Everything related to state transition is performed by beacon nodes even if they're not validators, and need no interaction with the execution chain, as they only apply blocks to states as a pure function.

However, validators that include their view of the execution chain in a block being built, do need access to the latest blocks, as described in the [eth1 data section](https://github.com/ethereum/consensus-specs/blob/v1.3.0/specs/phase0/validator.md#eth1-data) of the validator specs. To summarize:

- The consensus node gets blocks from the execution client and builds `Eth1Data` structs.
- A proposer at a slot `N` will need to build its eth1 vote for the voting period that started at slot `s = div(N, EPOCHS_PER_ETH1_VOTING_PERIOD)`. It will take  into account the execution blocks that are `ETH1_FOLLOW_DISTANCE` behind the current voting period.
- The vote is selected using the following priority:
  - An `eth1_data` that is present in the execution client and also in the beacon state `eth1_data_votes` list. If more than one match, the most frequent will be selected. That ways it tries to match a vote by a different node if present.
  - If no matches are found in the beacon state votes, it will default to the latest eth1 data available in the local execution client (within the expected range).
  - If nothing is found in the execution chain for the expected range, the last default is voting for the current `beacon_state.eth1_data`.

## Checkpoint sync

**TO DO**: document checkpoint sync.

## Next document

Let's go over [Fork Choice](fork_choice.md) to see a theoretical explanation of LMD GHOST.
