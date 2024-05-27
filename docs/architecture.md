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
