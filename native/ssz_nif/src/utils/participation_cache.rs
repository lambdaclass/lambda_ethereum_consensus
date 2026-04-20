//! Incremental merkle tree cache for BeaconState participation fields (15, 16).
//!
//! SSZ hashes `VariableList<u8, ValidatorRegistryLimit>` as a binary merkle tree
//! where every 32 u8 values are packed into one 32-byte leaf chunk.  With ~2.2M
//! validators the tree has ~68.75K populated leaves out of 2^35 total positions.
//!
//! On non-epoch blocks, only ~4K-8K participation entries change (attesting validators),
//! so rebuilding the entire tree is wasteful.  This module caches two trees (one for
//! previous_epoch_participation, one for current_epoch_participation) and updates
//! only the affected paths on subsequent calls.
//!
//! ## Tree layout
//!
//! A dense subtree covers the first `DENSE_LEAF_COUNT` (2^17 = 131072) leaf positions,
//! enough for 4.2M validators (32 u8s per chunk * 131072 chunks).  Above that, 18
//! sparse levels use precomputed zero-hashes.
//!
//! Dense flat array (1-indexed):
//!   nodes[1]                         = subtree root
//!   nodes[2], nodes[3]               = depth 1
//!   ...
//!   nodes[DENSE_LEAF_COUNT .. 2*DENSE_LEAF_COUNT - 1] = leaves (packed u8 chunks)

use std::sync::{LazyLock, Mutex};

use ethereum_hashing::{hash32_concat, ZERO_HASHES};

/// u8 packing factor: 32 u8s (32 bytes) per leaf chunk.
const PACKING_FACTOR: usize = 32;

/// Dense subtree depth.  2^17 = 131,072 leaf positions → supports up to 4.2M validators.
const DENSE_DEPTH: usize = 17;
const DENSE_LEAF_COUNT: usize = 1 << DENSE_DEPTH; // 131,072
const DENSE_NODE_COUNT: usize = 2 * DENSE_LEAF_COUNT; // 262,144

/// Total tree depth for `VariableList<u8, ValidatorRegistryLimit>`.
/// ValidatorRegistryLimit = 2^40 for all configs.  max_chunks = 2^40/32 = 2^35.  depth = 35.
const TOTAL_DEPTH: usize = 35;

struct ParticipationMerkleCache {
    /// Flat binary tree: nodes[1] = subtree root, leaves at [DENSE_LEAF_COUNT .. 2*DENSE_LEAF_COUNT).
    /// Index 0 is unused.
    nodes: Vec<[u8; 32]>,
    /// Cached participation values for diffing.
    values: Vec<u8>,
    /// Whether the cache has been initialized.
    valid: bool,
    /// The last computed root hash, used to validate fork consistency.
    last_root: [u8; 32],
}

impl ParticipationMerkleCache {
    fn new() -> Self {
        Self {
            nodes: Vec::new(),
            values: Vec::new(),
            valid: false,
            last_root: [0u8; 32],
        }
    }

    /// Build the full tree from scratch.
    fn initialize(&mut self, values: &[u8]) {
        let chunk_count = values.len().div_ceil(PACKING_FACTOR);
        assert!(
            chunk_count <= DENSE_LEAF_COUNT,
            "participation chunk count ({chunk_count}) exceeds dense tree capacity ({DENSE_LEAF_COUNT})"
        );

        // Allocate tree — initialize all nodes to zeros (matching SSZ zero-padding).
        self.nodes.clear();
        self.nodes.resize(DENSE_NODE_COUNT, [0u8; 32]);
        self.values = values.to_vec();

        // Pack values into leaf chunks.
        for c in 0..chunk_count {
            self.nodes[DENSE_LEAF_COUNT + c] = pack_chunk(values, c);
        }
        // Remaining leaf positions are already zero (SSZ default for unpopulated entries).

        // Build internal nodes bottom-up.
        for i in (1..DENSE_LEAF_COUNT).rev() {
            self.nodes[i] = hash32_concat(&self.nodes[2 * i], &self.nodes[2 * i + 1]);
        }

        self.valid = true;
    }

    /// Diff the new values against the cache, incrementally update changed paths,
    /// and return the final SSZ VariableList hash (content root + mix_in_length).
    fn update_and_root(&mut self, new_values: &[u8]) -> [u8; 32] {
        debug_assert!(self.valid);

        let old_len = self.values.len();
        let new_len = new_values.len();

        if new_len != old_len {
            // Value count changed (new validators added at epoch).  Rebuild.
            self.initialize(new_values);
            return self.finalize_root(new_len);
        }

        // Collect dirty chunk indices.
        let mut dirty_chunks: Vec<usize> = Vec::with_capacity(300);
        for i in 0..new_len {
            if new_values[i] != self.values[i] {
                let chunk_idx = i / PACKING_FACTOR;
                if dirty_chunks.last() != Some(&chunk_idx) {
                    dirty_chunks.push(chunk_idx);
                }
                self.values[i] = new_values[i];
            }
        }

        // Update dirty leaves and walk each path to subtree root.
        for &chunk_idx in &dirty_chunks {
            let leaf_idx = DENSE_LEAF_COUNT + chunk_idx;
            self.nodes[leaf_idx] = pack_chunk(&self.values, chunk_idx);

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
    /// Also stores the result as `last_root` for fork validation.
    fn finalize_root(&mut self, value_count: usize) -> [u8; 32] {
        let mut root = self.nodes[1]; // dense subtree root

        // Sparse levels: DENSE_DEPTH .. TOTAL_DEPTH-1
        // At each level, our subtree is the left child; right sibling is a zero-hash subtree.
        for level in DENSE_DEPTH..TOTAL_DEPTH {
            root = hash32_concat(&root, &ZERO_HASHES[level]);
        }

        // mix_in_length: hash(content_root || length_as_le_u256)
        let mut length_bytes = [0u8; 32];
        length_bytes[0..8].copy_from_slice(&(value_count as u64).to_le_bytes());
        let result = hash32_concat(&root, &length_bytes);
        self.last_root = result;
        result
    }
}

/// Pack 32 consecutive u8 values into a 32-byte SSZ chunk.
fn pack_chunk(values: &[u8], chunk_idx: usize) -> [u8; 32] {
    let mut chunk = [0u8; 32];
    let start = chunk_idx * PACKING_FACTOR;
    let end = (start + PACKING_FACTOR).min(values.len());
    let count = end - start;
    chunk[..count].copy_from_slice(&values[start..end]);
    chunk
}

// Two global caches: one for previous_epoch_participation, one for current_epoch_participation.
static PREV_PARTICIPATION_CACHE: LazyLock<Mutex<ParticipationMerkleCache>> =
    LazyLock::new(|| Mutex::new(ParticipationMerkleCache::new()));

static CURR_PARTICIPATION_CACHE: LazyLock<Mutex<ParticipationMerkleCache>> =
    LazyLock::new(|| Mutex::new(ParticipationMerkleCache::new()));

fn get_cache(field_num: u32) -> &'static Mutex<ParticipationMerkleCache> {
    match field_num {
        15 => &PREV_PARTICIPATION_CACHE,
        16 => &CURR_PARTICIPATION_CACHE,
        _ => panic!("Invalid participation field number: {field_num}"),
    }
}

/// Compute the SSZ tree hash root of a participation VariableList<u8> incrementally.
///
/// `field_num` is 15 (previous) or 16 (current).
/// On the first call, builds the full tree and caches it.  On subsequent calls, diffs
/// against the cached values and only rehashes affected paths.
pub fn hash_participation_incremental(field_num: u32, values: &[u8]) -> [u8; 32] {
    let mut cache = get_cache(field_num).lock().unwrap();
    if cache.valid {
        cache.update_and_root(values)
    } else {
        cache.initialize(values);
        cache.finalize_root(values.len())
    }
}

/// Apply targeted participation updates and return the new hash.
/// `field_num` is 15 (previous) or 16 (current).
/// `updates` is a list of (index, new_value) pairs.
/// `value_count` is the current total number of participation entries.
/// `expected_prev_hash` validates that the cache corresponds to the correct fork.
///
/// The cache must have been initialized by a prior `hash_participation_incremental` call.
/// If the cache is invalid, value_count doesn't match, or the expected hash doesn't
/// match, returns None (caller falls back to full hash).
pub fn apply_participation_updates(
    field_num: u32,
    updates: &[(u32, u8)],
    value_count: usize,
    expected_prev_hash: &[u8; 32],
) -> Option<[u8; 32]> {
    let mut cache = get_cache(field_num).lock().unwrap();
    if !cache.valid || cache.values.len() != value_count || &cache.last_root != expected_prev_hash {
        return None;
    }

    // Apply updates and collect dirty chunks.
    let mut dirty_chunks: Vec<usize> = Vec::with_capacity(updates.len() / PACKING_FACTOR + 1);
    for &(idx, new_val) in updates {
        let i = idx as usize;
        if i < cache.values.len() {
            cache.values[i] = new_val;
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
        cache.nodes[leaf_idx] = pack_chunk(&cache.values, chunk_idx);

        let mut pos = leaf_idx >> 1;
        while pos >= 1 {
            cache.nodes[pos] = hash32_concat(&cache.nodes[2 * pos], &cache.nodes[2 * pos + 1]);
            pos >>= 1;
        }
    }

    Some(cache.finalize_root(value_count))
}

/// Reset a participation cache.
#[allow(dead_code)]
pub fn reset_participation_cache(field_num: u32) {
    get_cache(field_num).lock().unwrap().valid = false;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Compute the participation hash the "original" way (full tree via ssz_types + tree_hash)
    /// for comparison.
    fn reference_hash(values: &[u8]) -> [u8; 32] {
        use ssz_types::typenum::U1099511627776;
        use ssz_types::VariableList;
        use tree_hash::TreeHash;

        let list = VariableList::<u8, U1099511627776>::new(values.to_vec()).unwrap();
        list.tree_hash_root().0
    }

    #[test]
    fn empty_participation() {
        reset_participation_cache(15);
        let values: Vec<u8> = vec![];
        assert_eq!(
            hash_participation_incremental(15, &values),
            reference_hash(&values)
        );
    }

    #[test]
    fn small_participation() {
        reset_participation_cache(15);
        let values: Vec<u8> = vec![7; 100];
        assert_eq!(
            hash_participation_incremental(15, &values),
            reference_hash(&values)
        );
    }

    #[test]
    fn incremental_update() {
        reset_participation_cache(16);
        let mut values: Vec<u8> = vec![0; 1000];

        // First call: builds cache
        let h1 = hash_participation_incremental(16, &values);
        assert_eq!(h1, reference_hash(&values));

        // Modify a few entries (simulating attestation flag updates)
        values[42] = 7;
        values[500] = 3;
        values[999] = 5;

        // Second call: incremental update
        let h2 = hash_participation_incremental(16, &values);
        assert_eq!(h2, reference_hash(&values));
        assert_ne!(h1, h2);
    }

    #[test]
    fn cross_chunk_boundary() {
        reset_participation_cache(15);
        let mut values: Vec<u8> = vec![0; 64]; // 2 chunks

        let h1 = hash_participation_incremental(15, &values);
        assert_eq!(h1, reference_hash(&values));

        // Change last element of chunk 0 and first element of chunk 1
        values[31] = 7;
        values[32] = 3;

        let h2 = hash_participation_incremental(15, &values);
        assert_eq!(h2, reference_hash(&values));
    }

    #[test]
    fn targeted_updates() {
        reset_participation_cache(15);
        let mut values: Vec<u8> = vec![0; 1000];

        // Initialize cache via full hash
        let _h1 = hash_participation_incremental(15, &values);

        // Apply targeted updates (simulating attestation flags)
        let updates: Vec<(u32, u8)> = vec![(42, 7), (500, 3), (999, 5)];
        // Also update our reference copy
        values[42] = 7;
        values[500] = 3;
        values[999] = 5;

        let h2 = apply_participation_updates(15, &updates, 1000, &_h1).unwrap();
        assert_eq!(h2, reference_hash(&values));
    }

    #[test]
    fn targeted_updates_returns_none_when_invalid() {
        reset_participation_cache(16);
        let updates = vec![(0, 7u8)];
        let fake_hash = [0u8; 32];
        assert_eq!(
            apply_participation_updates(16, &updates, 100, &fake_hash),
            None
        );
    }

    #[test]
    fn separate_caches_for_prev_and_curr() {
        reset_participation_cache(15);
        reset_participation_cache(16);

        let prev_values: Vec<u8> = vec![7; 100];
        let curr_values: Vec<u8> = vec![3; 100];

        let h_prev = hash_participation_incremental(15, &prev_values);
        let h_curr = hash_participation_incremental(16, &curr_values);

        assert_eq!(h_prev, reference_hash(&prev_values));
        assert_eq!(h_curr, reference_hash(&curr_values));
        assert_ne!(h_prev, h_curr);
    }
}
