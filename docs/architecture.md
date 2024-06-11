# Architecture of the consensus node

## Processes summary

### Supervision tree

This is our complete supervision tree.

```mermaid
graph LR
Application[Application <br> <:one_for_one>]
BeaconNode[BeaconNode <br> <:one_for_all>]
P2P.IncomingRequests[P2P.IncomingRequests <br> <:one_for_one>]
ValidatorManager[ValidatorManager <br> <:one_for_one>]
Telemetry[Telemetry <br> <:one_for_one>]

Application --> Telemetry
Application --> DB
Application --> Blocks
Application --> BlockStates
Application --> Metadata
Application --> BeaconNode
Application --> BeaconApi.Endpoint

BeaconNode -->|genesis_time,<br>genesis_validators_root,<br> fork_choice_data, time| BeaconChain 
BeaconNode -->|store, head_slot, time| ForkChoice
BeaconNode -->|listen_addr, <br>enable_discovery, <br> discovery_addr, <br>bootnodes| P2P.Libp2pPort
BeaconNode --> P2P.Peerbook
BeaconNode --> P2P.IncomingRequests
BeaconNode --> PendingBlocks
BeaconNode --> SyncBlocks
BeaconNode --> Attestation
BeaconNode --> BeaconBlock
BeaconNode --> BlobSideCar
BeaconNode --> OperationsCollector
BeaconNode -->|slot, head_root| ValidatorManager
BeaconNode -->|genesis_time, snapshot, votes| ExecutionChain
ValidatorManager --> ValidatorN

P2P.IncomingRequests --> IncomingRequests.Handler
P2P.IncomingRequests --> IncomingRequests.Receiver

Telemetry --> :telemetry_poller
Telemetry --> TelemetryMetricsPrometheus
```

Each box is a process. If it has children, it's a supervisor, with it's restart strategy clarified. 

If it's a leaf in the tree, it's a GenServer, task, or other non-supervisor process. The tags in the edges/arrows are the init args passed on children init (start or restart after crash).

### High level interaction

This is the high level interaction between the processes.

```mermaid
graph LR

ExecutionChain

BlobDb
BlockDb

subgraph "P2P"
    Libp2pPort
    Peerbook
    IncomingRequests
    Attestation
    BeaconBlock
    BlobSideCar
    Metadata
end

subgraph "Node"
    Validator
    BeaconChain
    ForkChoice
    PendingBlocks
    OperationsCollector
end

BeaconChain <-->|on_tick <br> get_fork_digest, get_| Validator
BeaconChain -->|on_tick| BeaconBlock
BeaconChain <-->|on_tick <br> update_fork_choice_cache| ForkChoice
BeaconBlock -->|add_block| PendingBlocks
Validator -->|get_eth1_data <br>to build blocks| ExecutionChain
Validator -->|publish block| Libp2pPort
Validator -->|collect, stop_collecting| Attestation
Validator -->|get slashings, <br>attestations,<br> voluntary exits|OperationsCollector
Validator -->|store_blob| BlobDb
ForkChoice -->|notify new block|Validator
ForkChoice <-->|notify new block <br> on_attestation|OperationsCollector
ForkChoice -->|notify new block|ExecutionChain
ForkChoice -->|store_block| BlockDb
PendingBlocks -->|on_block| ForkChoice
PendingBlocks -->|get_blob_sidecar|BlobDb
Libp2pPort <-->|gosipsub <br> validate_message| BlobSideCar
Libp2pPort <-->|gossipsub <br> validate_message<br> subscribe_to_topic| BeaconBlock
Libp2pPort <-->|gossipsub <br> validate_message<br> subscribe_to_topic| Attestation
Libp2pPort -->|store_blob| BlobDb
Libp2pPort -->|new_peer| Peerbook
BlobSideCar -->|store_blob| BlobDb
Attestation -->|set_attnet|Metadata
IncomingRequests -->|get seq_number|Metadata
PendingBlocks -->|penalize/get<br>on downloading|Peerbook
Libp2pPort -->|new_request| IncomingRequests
```

## Sequences

This section contains sequence diagrams representing the interaction of processes through time in response to a stimulus. The main entry point for new events is through gossip and request-response protocols, which is how nodes communicates between each other.

Request-response is a simple protocol where client request for specific data such as old blocks that they may be missing or other clients metadata.

Gossip allows clients to subscribe to different topics (hence the name "gossipsub") they are interested in, and get updates for them. This is how a node receives new blocks or attestations from their peers.

We use the `go-libp2p` library for the networking primitives, which is an implementation of the `libp2p` networking stack. We use ports to communicate with a go application and Broadway to process notifications. This port has a GenServer owner called `Libp2pPort`.

# Gossipsub

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

### Checkpoint sync

**TO DO**: document checkpoint sync.

## Next document

Let's go over [Fork Choice](fork_choice.md) to see a theoretical explanation of LMD GHOST.
