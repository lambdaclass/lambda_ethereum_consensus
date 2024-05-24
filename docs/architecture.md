# Architecture of the consensus node

## Processes

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
BeaconNode -->|store, head_slot| ForkChoice
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
BeaconNode --> ExecutionChain
ValidatorManager --> ValidatorN

P2P.IncomingRequests --> IncomingRequests.Handler
P2P.IncomingRequests --> IncomingRequests.Receiver

Telemetry --> :telemetry_poller
Telemetry --> TelemetryMetricsPrometheus
```

Each box is a process. If it has children, it's a supervisor, with it's restart strategy clarified. 

If it's a leaf in the tree, it's a GenServer, task, or other non-supervisor process. The tags in the edges/arrows are the init args passed on children init (start or restart after crash).

## Block diagram

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


## Networking

The main entry for new events is the gossip protocol, which is how our consensus node communicates with other consensus nodes. This includes:

1. Discovery: our node has a series of known `bootnodes` hardcoded. We request a list of the nodes they know about and add them to our list. We save them locally and now can use those too to request new nodes.
2. Message propagation. When a proposer sends a new block, or validators attest for a new block, they send those to other known nodes. Those, in turn, propagate the messages sent to other nodes. This process is repeated until, ideally, the whole network receives the messages.

We use the `go-libp2p` library for the networking primitives, which is an implementation of the `libp2p` networking stack.

We use ports to communicate with a go application and Broadway to process notifications.

**TO DO**: We need to document the port's architecture.

## Gossipsub

One of the main communication protocols is GossipSub. This allows us to tell peers which topics we're interested in and receive events for them. The main external events we react to are blocks and attestations.

### Receiving an attestation

```mermaid
sequenceDiagram
    participant prod as Topic Producer (GenStage)
    participant proc as Topic Processor (Broadway)
    participant FC as Fork-choice store

    prod ->> proc: Produce demand
    proc ->> proc: Decompress and deserialize message
    proc ->>+ proc: on_attestation()
    proc ->> FC: request latest message by the same validator
    FC -->> proc: return
    proc ->> proc: Validate attestation
    proc ->>- FC: Update fork-choice store weights
```

When receiving an attestation, it's processed by the [on_attestation](https://eth2book.info/capella/annotated-spec/#on_attestation) callback. We just validate it and send it to the fork choice store to update its weights and target checkpoints. The attestation is only processed if this attestation is the latest message by that validator. If there's a newer one, it should be discarded.

The most relevant piece of the spec here is the [get_weight](https://eth2book.info/capella/annotated-spec/#get_weight) function, which is the core of the fork-choice algorithm. In the specs, this function is called on demand, when calling [get_head](https://eth2book.info/capella/annotated-spec/#get_head), works with the store's values, and recalculates them each time. In our case, we cache the weights and the head root each time we add a block or attestation, so we don't need to do the same calculations again. 

**To do**: we should probably save the latest messages in persistent storage as well so that if the node crashes we can recover the tree weights.

### Receiving a block

```mermaid
sequenceDiagram
    participant prod as Topic Producer (GenStage)
    participant proc as Topic Processor (Broadway)
    participant block as Block DB
    participant state as Beacon States DB
    participant FC as Fork-choice store
    participant exec as Execution Client

    prod ->> proc: Produce demand
    proc ->> proc: Decompress and deserialize message
    proc ->>+ proc: on_block(block)
    proc ->> exec: Validate execution payload
    exec -->> proc: ok
    proc ->> FC: request validation metadata
    FC -->> proc: return
    proc ->> proc: Validate block
    proc ->> block: Save new block
    proc ->> proc: Calculate state transition
    proc ->> state: Save new beacon state metadata
    proc ->> FC: Add a new block to the tree and update weights
    loop
        proc ->>- proc: process_operations
    end
    loop
        proc ->> proc: on_attestation
    end
```

Receiving a block is more complex:

- The block itself needs to be stored.
- The state transition needs to be applied, a new beacon state calculated, and stored separately.
- A new node needs to be added to the block tree aside from updating weights.
- on_attestation needs to be called for each attestation.

Also, there's a more complex case: we can only include a block in the fork tree if we know of its parents and their connection with our current finalized checkpoint. If we receive a disconnected node, we'll need to use Request-Response to ask peers for the missing blocks.

## Request-Response

**TO DO**: document how ports work for this.

### Pending blocks

**TO DO**: document pending blocks design.

### Checkpoint sync

**TO DO**: document checkpoint sync.


## Next document

Let's go over [Fork Choice](fork_choice.md) to see a theoretical explanation of LMD GHOST.
