//! Incremental merkle tree cache for BeaconState balances (field 12).
//!
//! SSZ hashes `VariableList<u64, ValidatorRegistryLimit>` as a binary merkle tree
//! where every 4 u64 values are packed into one 32-byte leaf chunk.  With ~2.2M
//! validators the tree has ~550K populated leaves out of 2^38 total positions.
//!
//! On non-epoch blocks only ~528 balances change (512 sync committee + 16 withdrawals),
//! so rebuilding the entire tree is extremely wasteful.  This module caches the tree
//! and updates only the affected paths on subsequent calls.
//!
//! ## Tree layout
//!
//! A dense subtree covers the first `DENSE_LEAF_COUNT` (2^20 = 1M) leaf positions,
//! enough for 4M validators.  Above that, 18 sparse levels use precomputed zero-hashes.
//!
//! Dense flat array (1-indexed):
//!   nodes[1]                         = subtree root
//!   nodes[2], nodes[3]               = depth 1
//!   ...
//!   nodes[DENSE_LEAF_COUNT .. 2*DENSE_LEAF_COUNT - 1] = leaves (packed u64 chunks)

use std::sync::{LazyLock, Mutex};

use ethereum_hashing::{hash32_concat, ZERO_HASHES};

/// u64 packing factor: 4 u64s (32 bytes) per leaf chunk.
const PACKING_FACTOR: usize = 4;

/// Dense subtree depth.  2^20 = 1,048,576 leaf positions → supports up to 4M validators.
const DENSE_DEPTH: usize = 20;
const DENSE_LEAF_COUNT: usize = 1 << DENSE_DEPTH; // 1,048,576
const DENSE_NODE_COUNT: usize = 2 * DENSE_LEAF_COUNT; // 2,097,152

/// Total tree depth for `VariableList<u64, ValidatorRegistryLimit>`.
/// ValidatorRegistryLimit = 2^40 for all configs.  max_chunks = 2^40/4 = 2^38.  depth = 38.
const TOTAL_DEPTH: usize = 38;

struct BalanceMerkleCache {
    /// Flat binary tree: nodes[1] = subtree root, leaves at [DENSE_LEAF_COUNT .. 2*DENSE_LEAF_COUNT).
    /// Index 0 is unused.
    nodes: Vec<[u8; 32]>,
    /// Cached balance values for diffing.
    balances: Vec<u64>,
    /// Whether the cache has been initialized.
    valid: bool,
}

impl BalanceMerkleCache {
    fn new() -> Self {
        Self {
            nodes: Vec::new(),
            balances: Vec::new(),
            valid: false,
        }
    }

    /// Build the full tree from scratch.
    fn initialize(&mut self, balances: &[u64]) {
        let chunk_count = balances.len().div_ceil(PACKING_FACTOR);
        assert!(
            chunk_count <= DENSE_LEAF_COUNT,
            "balance chunk count ({chunk_count}) exceeds dense tree capacity ({DENSE_LEAF_COUNT})"
        );

        // Allocate tree — initialize all nodes to zeros (matching SSZ zero-padding).
        self.nodes.clear();
        self.nodes.resize(DENSE_NODE_COUNT, [0u8; 32]);
        self.balances = balances.to_vec();

        // Pack balances into leaf chunks.
        for c in 0..chunk_count {
            self.nodes[DENSE_LEAF_COUNT + c] = pack_chunk(balances, c);
        }
        // Remaining leaf positions are already zero (SSZ default for unpopulated entries).

        // Build internal nodes bottom-up.
        for i in (1..DENSE_LEAF_COUNT).rev() {
            self.nodes[i] = hash32_concat(&self.nodes[2 * i], &self.nodes[2 * i + 1]);
        }

        self.valid = true;
    }

    /// Diff the new balances against the cache, incrementally update changed paths,
    /// and return the final SSZ VariableList hash (content root + mix_in_length).
    fn update_and_root(&mut self, new_balances: &[u64]) -> [u8; 32] {
        debug_assert!(self.valid);

        let old_len = self.balances.len();
        let new_len = new_balances.len();

        if new_len != old_len {
            // Balance count changed (new validators added at epoch).  Rebuild.
            self.initialize(new_balances);
            return self.finalize_root(new_len);
        }

        // Collect dirty chunk indices.
        let mut dirty_chunks: Vec<usize> = Vec::with_capacity(600); // ~528 typical
        for i in 0..new_len {
            if new_balances[i] != self.balances[i] {
                let chunk_idx = i / PACKING_FACTOR;
                if dirty_chunks.last() != Some(&chunk_idx) {
                    dirty_chunks.push(chunk_idx);
                }
                self.balances[i] = new_balances[i];
            }
        }

        // Update dirty leaves and walk each path to subtree root.
        for &chunk_idx in &dirty_chunks {
            let leaf_idx = DENSE_LEAF_COUNT + chunk_idx;
            self.nodes[leaf_idx] = pack_chunk(&self.balances, chunk_idx);

            let mut pos = leaf_idx >> 1;
            while pos >= 1 {
                self.nodes[pos] = hash32_concat(&self.nodes[2 * pos], &self.nodes[2 * pos + 1]);
                pos >>= 1;
            }
        }

        self.finalize_root(new_len)
    }

    /// Walk through sparse levels from dense subtree root to content root,
    /// then mix_in_length for the final SSZ VariableList hash.
    fn finalize_root(&self, balance_count: usize) -> [u8; 32] {
        let mut root = self.nodes[1]; // dense subtree root

        // Sparse levels: DENSE_DEPTH .. TOTAL_DEPTH-1
        // At each level, our subtree is the left child; right sibling is a zero-hash subtree.
        for level in DENSE_DEPTH..TOTAL_DEPTH {
            root = hash32_concat(&root, &ZERO_HASHES[level]);
        }

        // mix_in_length: hash(content_root || length_as_le_u256)
        let mut length_bytes = [0u8; 32];
        length_bytes[0..8].copy_from_slice(&(balance_count as u64).to_le_bytes());
        hash32_concat(&root, &length_bytes)
    }
}

/// Pack 4 consecutive u64 values into a 32-byte SSZ chunk (little-endian).
fn pack_chunk(balances: &[u64], chunk_idx: usize) -> [u8; 32] {
    let mut chunk = [0u8; 32];
    let start = chunk_idx * PACKING_FACTOR;
    for i in 0..PACKING_FACTOR {
        let idx = start + i;
        if idx < balances.len() {
            chunk[i * 8..(i + 1) * 8].copy_from_slice(&balances[idx].to_le_bytes());
        }
    }
    chunk
}

static BALANCE_CACHE: LazyLock<Mutex<BalanceMerkleCache>> =
    LazyLock::new(|| Mutex::new(BalanceMerkleCache::new()));

/// Compute the SSZ tree hash root of a `VariableList<u64, ValidatorRegistryLimit>` incrementally.
///
/// On the first call, builds the full tree and caches it.  On subsequent calls, diffs
/// against the cached balances and only rehashes affected paths.
///
/// Returns the final 32-byte hash (content root with mix_in_length).
pub fn hash_balances_incremental(balances: &[u64]) -> [u8; 32] {
    let mut cache = BALANCE_CACHE.lock().unwrap();
    if cache.valid {
        cache.update_and_root(balances)
    } else {
        cache.initialize(balances);
        cache.finalize_root(balances.len())
    }
}

/// Apply targeted balance updates and return the new hash.
/// `updates` is a list of (index, new_value) pairs.
/// `balance_count` is the current total number of balances.
///
/// The cache must have been initialized by a prior `hash_balances_incremental` call.
/// If the cache is invalid or balance_count doesn't match, returns None (caller
/// should fall back to the full hash path).
pub fn apply_updates_and_hash(updates: &[(u32, u64)], balance_count: usize) -> Option<[u8; 32]> {
    let mut cache = BALANCE_CACHE.lock().unwrap();
    if !cache.valid || cache.balances.len() != balance_count {
        return None;
    }

    // Apply updates and collect dirty chunks.
    let mut dirty_chunks: Vec<usize> = Vec::with_capacity(updates.len() / 4 + 1);
    for &(idx, new_val) in updates {
        let i = idx as usize;
        if i < cache.balances.len() {
            cache.balances[i] = new_val;
            let chunk_idx = i / PACKING_FACTOR;
            if dirty_chunks.last() != Some(&chunk_idx) {
                dirty_chunks.push(chunk_idx);
            }
        }
    }

    // Sort dirty chunks to ensure dedup works correctly (updates may not be ordered).
    dirty_chunks.sort_unstable();
    dirty_chunks.dedup();

    // Update dirty leaves and walk each path to subtree root.
    for &chunk_idx in &dirty_chunks {
        let leaf_idx = DENSE_LEAF_COUNT + chunk_idx;
        cache.nodes[leaf_idx] = pack_chunk(&cache.balances, chunk_idx);

        let mut pos = leaf_idx >> 1;
        while pos >= 1 {
            cache.nodes[pos] = hash32_concat(&cache.nodes[2 * pos], &cache.nodes[2 * pos + 1]);
            pos >>= 1;
        }
    }

    Some(cache.finalize_root(balance_count))
}

/// Reset the balance cache.  Should be called when the balance vector is resized
/// (e.g., after epoch processing that adds new validators).
pub fn reset_balance_cache() {
    BALANCE_CACHE.lock().unwrap().valid = false;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Compute the balance hash the "original" way (full tree via ssz_types + tree_hash)
    /// for comparison.
    fn reference_hash(balances: &[u64]) -> [u8; 32] {
        use ssz_types::typenum::U1099511627776;
        use ssz_types::VariableList;
        use tree_hash::TreeHash;

        let list = VariableList::<u64, U1099511627776>::new(balances.to_vec()).unwrap();
        list.tree_hash_root().0
    }

    #[test]
    fn empty_balances() {
        reset_balance_cache();
        let balances: Vec<u64> = vec![];
        assert_eq!(
            hash_balances_incremental(&balances),
            reference_hash(&balances)
        );
    }

    #[test]
    fn small_balances() {
        reset_balance_cache();
        let balances: Vec<u64> = vec![32_000_000_000; 100];
        assert_eq!(
            hash_balances_incremental(&balances),
            reference_hash(&balances)
        );
    }

    #[test]
    fn incremental_update() {
        reset_balance_cache();
        let mut balances: Vec<u64> = vec![32_000_000_000; 1000];

        // First call: builds cache
        let h1 = hash_balances_incremental(&balances);
        assert_eq!(h1, reference_hash(&balances));

        // Modify a few balances (simulating sync + withdrawals)
        balances[42] += 1_000_000;
        balances[500] -= 500_000;
        balances[999] = 0;

        // Second call: incremental update
        let h2 = hash_balances_incremental(&balances);
        assert_eq!(h2, reference_hash(&balances));
        assert_ne!(h1, h2);
    }

    #[test]
    fn cross_chunk_boundary() {
        reset_balance_cache();
        let mut balances: Vec<u64> = vec![1; 8]; // 2 chunks

        let h1 = hash_balances_incremental(&balances);
        assert_eq!(h1, reference_hash(&balances));

        // Change last element of chunk 0 and first element of chunk 1
        balances[3] = 99;
        balances[4] = 99;

        let h2 = hash_balances_incremental(&balances);
        assert_eq!(h2, reference_hash(&balances));
    }

    #[test]
    fn targeted_updates() {
        reset_balance_cache();
        let mut balances: Vec<u64> = vec![32_000_000_000; 1000];

        // Initialize cache via full hash
        let _h1 = hash_balances_incremental(&balances);

        // Apply targeted updates (simulating sync + withdrawal)
        let updates: Vec<(u32, u64)> = vec![
            (42, balances[42] + 1_000_000),
            (500, balances[500].saturating_sub(500_000)),
            (999, 0),
        ];
        // Also update our reference copy
        balances[42] += 1_000_000;
        balances[500] -= 500_000;
        balances[999] = 0;

        let h2 = apply_updates_and_hash(&updates, 1000).unwrap();
        assert_eq!(h2, reference_hash(&balances));
    }

    #[test]
    fn targeted_updates_returns_none_when_invalid() {
        reset_balance_cache();
        let updates = vec![(0, 100u64)];
        assert_eq!(apply_updates_and_hash(&updates, 100), None);
    }

    #[test]
    fn balance_count_change_triggers_rebuild() {
        reset_balance_cache();
        let balances: Vec<u64> = vec![32_000_000_000; 100];
        let h1 = hash_balances_incremental(&balances);
        assert_eq!(h1, reference_hash(&balances));

        // Add a new validator (epoch boundary deposit)
        let mut balances2 = balances.clone();
        balances2.push(32_000_000_000);
        let h2 = hash_balances_incremental(&balances2);
        assert_eq!(h2, reference_hash(&balances2));
        assert_ne!(h1, h2);
    }
}
