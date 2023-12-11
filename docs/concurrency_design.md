# Store concurrency design

## Current situation

The following is a sequence diagram on the lifecycle of a block, from the moment its notification arrives in the LibP2P port and until it's processed and saved. Each lane is a separate process and may encompass many different modules.

```mermaid
sequenceDiagram

participant port as LibP2P Port <br> (Genserver)
participant sub as Subscriber <br> (GenStage)
participant consumer as GossipConsumer <br> (broadway)
participant pending as Pending Blocks <br> (GenServer)
participant store as Fork-choice store (GenServer)
participant DB as KV Store

port ->> sub: gossip(id)
sub ->> port: accept(id)
sub ->> consumer: handle_demand
consumer ->> consumer: decompress <br> decode <br> call handler
consumer ->> pending: decoded block
pending ->> store: has_block(block)
store -->> pending: false
pending ->> store: has_block(parent)
store -->> pending: true
pending ->> store: on_block(block)
store ->> store: validate block <br> calculate state transition <br> add state
store ->> DB: store block
store -->> pending: :ok
```

Let's look at the main issues and some improvements that may help with them.

### Blocking Calls

`Store.on_block(block)` (write operation) is blocking. This operation is particularly big, as it performs the state transition. These causes some issues:

- It's a call, so the calling process (in our case the pending blocks processor) will be blocked until the state transition is finished. No further blocks will be downloaded while this happens.
- Any other store call (adding an attestation, checking if a block is present) will be blocked. 

Improvements:

- Making it a `cast`. The caller doesn't immediately need to know what's the result of the state transition. We can do that an async operation.
- Making the state transition be calculated in an async way, so the store can take other work like adding attestations while the cast happens.

### Concurrent downloads

Downloading a block is:

- A heavy IO operation (non-cpu consuming).
- Independent from downloading a different block.

Improvements:
- We should consider, instead of downloading them in sequence, downloading them in different tasks.

### Big Objects in Mailboxes

Blocks are pretty big objects and they are passed around in process mailboxes even for simple calls like `Store.has_block(block)`. We should minimize this kind of interactions as putting big structures in mailboxes slows their processing down.

Improvements:

- We could store the blocks in the DB immediately after downloading them.
- Checking if a block is present could be done directly with the DB, without need to check the store.
- If we want faster access for blocks, we can build an ETS block cache.

### Other issues

- States aren't ever stored in the DB. This is not a concurrency issue, but we should fix it.
- Low priority, but we should evaluate dropping the Subscriber genserver and broadway, and have one task per message under a supervisor.

## State Diagram

These are the states that a block may have:

- New: just downloaded, decompressed and decoded
- Pending: no parent.
- Child. Parent is present and downloaded.
- BlockChild: Parent is a valid block.
- StateChild: Parent’s state transition is calculated.
- Included: we calculated the state transition for this block and the state is available. It's now part of the fork tree.

The block diagram looks something like this:

```mermaid
stateDiagram-v2
	[*] --> New: Download, decompress, decode
	New --> Child: Parent is present
	New --> Pending: Parent is not present
	Pending --> Child: Parent is downloaded
	Child --> BlockChild: Parent is a valid block (but not a state)
	Child --> Invalid: Parent is Invalid
	BlockChild --> Invalid: store validation fails
	BlockChild --> StateChild: Parent state is present
	StateChild --> NewState: state transition calculated
	StateChild --> Invalid: state transition fails
```

### A possible new design

```mermaid
sequenceDiagram
  participant port as LibP2P Port <br> (Genserver)
  participant decoder as Decoder <br> (Supervised task)
	participant tracker as Block Tracker <br> (GenServer)
	participant down as Downloader <br> (Supervised task)
	participant store as Fork Choice Store <br> (Genserver)
	participant state_t as State Transition Task <br> (Supervised task)
	participant DB as KV Store
	
	port ->> decoder: gossip(id)
	decoder ->> port: accept(id)
	decoder ->> decoder: decompress <br> decode <br> call handler
	decoder ->> DB: store_block_if_not_present(block)
	decoder ->> tracker: new_block(root)
	tracker ->> DB: present?(parent_root)
	DB -->> tracker: false
	tracker ->> down: download(parent_root) 
	down ->> DB: store_block_if_not_present(parent_root)
	down ->> tracker: downloaded(parent_root)
	tracker ->> store: on_block(root)
	store ->> DB: get_block(root)
	store ->> store: validate block
	store ->> state_t: state_transition(block)
	state_t ->> DB: store_state(new_state)
	state_t ->> store: on_state(new_state)
	state_t ->> tracker: on_state(new_state)
```

Some pending definitions:

- The block tracker could eventually be a block cache, and maintain blocks and their state in an ETS that can be accessed easily by other processes.
