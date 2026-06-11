# Block Processing Benchmarks

Reproducible benchmarks for measuring block processing performance on real mainnet/testnet data. The workflow has two steps: download data from a Beacon API node, then replay blocks through the `ForkChoice.process_block` pipeline offline.

## Quick Start

```bash
# 1. Download 2 epochs (64 slots) from a Fulu-compatible node
mix bench.download \
  --url http://localhost:5052 \
  --start-slot 9649056 \
  --count 64

# 2. Run the benchmark
mix bench.blocks --data-dir bench/data/slot_9649056_64
```

## Step 1: Download Data

`mix bench.download` fetches state, blocks, and blob sidecars from a Beacon API, converts blobs to data columns (via KZG cell computation), and saves everything to disk.

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--url` | yes | | Beacon API base URL (e.g. `http://localhost:5052`) |
| `--start-slot` | yes | | Slot to anchor from (should be an epoch boundary) |
| `--count` | yes | | Number of slots after start to fetch |
| `--data-dir` | no | `bench/data` | Base directory for output |
| `--network` | no | `mainnet` | Network config (mainnet, sepolia, holesky, etc.) |

### Choosing a Start Slot

Pick a slot that is an **epoch boundary** (divisible by 32). This ensures the anchor state is at the start of an epoch, which is the natural checkpoint alignment for the forkchoice store. The task warns if the slot is not aligned.

To find a recent finalized epoch boundary:

```bash
# Query finalized slot from your beacon node
curl -s http://localhost:5052/eth/v1/beacon/headers/finalized | jq '.data.header.message.slot'
# Round down to epoch boundary: slot - (slot % 32)
```

### Output Structure

```
bench/data/slot_<start>_<count>/
  metadata.json              # Download parameters + timestamp + network
  state.ssz_snappy           # Anchor state (BeaconState) at start-slot
  block_<slot>.ssz_snappy    # Anchor block + all non-empty blocks in range
  columns_<slot>/            # Data columns per block (Fulu, only if block has blobs)
    column_<index>.ssz_snappy
```

Missing block files mean the slot was empty (no block proposed). This is normal; mainnet typically has ~1-3% empty slots.

### Requirements

The Beacon API node must:
- Serve the `/eth/v2/debug/beacon/states/{slot}` endpoint (SSZ)
- Serve the `/eth/v2/beacon/blocks/{slot}` endpoint (SSZ)
- Serve the `/eth/v1/beacon/blob_sidecars/{slot}` endpoint (JSON)
- Have state and blocks available for the requested slot range (not pruned)
- Be on the same fork as the compiled `.fork_version` (currently Fulu)

## Step 2: Process Blocks

`mix bench.blocks` loads cached data from disk, boots the necessary infrastructure (LevelDB, ETS caches, mocked execution engine), and replays blocks through the full `ForkChoice.process_block` pipeline.

### Options

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--data-dir` | yes | | Path to a downloaded dataset directory |
| `--log-level` | no | `info` | Logger level (`debug`, `info`, `warning`, `error`) |

### What Gets Booted

The task starts a minimal subset of the supervision tree, matching the `db` operation mode:

- LevelDB (temporary directory, discarded after run)
- ETS caches (Blocks, BlockStates, CheckpointStates)
- StateTransition cache
- Task supervisors (for async state storage and pruning)
- Mocked Engine API (always returns `VALID` for execution payloads)

No networking, no Beacon API, no validator logic.

### Example Output

```
=== Block Processing Benchmark ===
Slots:     9649056 -> 9649120
Blocks:    61 / 64 (3 empty slots)
Epochs:    2 boundaries crossed

Total time:     18.7s
Avg per block:  306ms
Epoch blocks:   [slot 9649088: 8.2s]
Non-epoch avg:  14ms
```

At `info` log level, each block also emits per-step timings from the state transition:

```
[on_block] slot=9649088 root=A1B2C3D4 epoch=true epoch.justification_and_finalization=1200ms epoch.rewards_and_penalties=3400ms ...
```

Use `--log-level warning` to suppress per-block logs and see only the summary.

## Typical Ranges for Benchmarking

| Goal | Suggested `--count` | Notes |
|------|-------------------|-------|
| Quick sanity check | 32 (1 epoch) | Fast, but only 1 epoch boundary |
| Standard benchmark | 64-128 (2-4 epochs) | Good balance of data and runtime |
| Full performance profile | 200+ (6+ epochs) | Multiple epoch boundaries, better averages |
| Epoch-only analysis | 32 | Start at slot N-1 of epoch boundary to isolate epoch cost |

## Reusing Downloaded Data

Downloaded datasets are self-contained (state + blocks + columns + metadata) and can be:
- Shared between team members (copy the directory)
- Rerun after code changes to compare before/after
- Stored long-term as regression baselines

The `bench/data/` directory is gitignored.
