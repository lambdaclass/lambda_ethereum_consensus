//! Incremental merkle tree cache for BeaconState randao_mixes (field 13).
//!
//! SSZ hashes `FixedVector<Bytes32, EpochsPerHistoricalVector>` as a binary merkle tree
//! where each 32-byte entry is one leaf (no packing needed).  With 65536 entries
//! (mainnet), only 1 entry changes per block, so rebuilding is wasteful.
//!
//! This module caches the tree and updates only the 16 nodes on the path from
//! the modified leaf to the root (~16 hash operations instead of ~65536).

use std::sync::{LazyLock, Mutex};

use ethereum_hashing::hash32_concat;

struct RandaoMerkleCache {
    /// Flat binary tree: nodes[1] = root, leaves at [leaf_count .. 2*leaf_count).
    nodes: Vec<[u8; 32]>,
    /// Number of leaf positions (next power of 2 >= vector size).
    leaf_count: usize,
    /// Whether the cache has been initialized.
    valid: bool,
    /// The last computed root hash for fork validation.
    last_root: [u8; 32],
}

impl RandaoMerkleCache {
    fn new() -> Self {
        Self {
            nodes: Vec::new(),
            leaf_count: 0,
            valid: false,
            last_root: [0u8; 32],
        }
    }

    /// Build the full tree from scratch.
    fn initialize(&mut self, values: &[[u8; 32]]) {
        let leaf_count = values.len().next_power_of_two();
        let node_count = 2 * leaf_count;
        self.leaf_count = leaf_count;

        self.nodes.resize(node_count, [0u8; 32]);

        // Copy values directly as leaves (no packing needed).
        for (i, v) in values.iter().enumerate() {
            self.nodes[self.leaf_count + i] = *v;
        }
        // Zero remaining leaves.
        for i in values.len()..self.leaf_count {
            self.nodes[self.leaf_count + i] = [0u8; 32];
        }

        // Build internal nodes bottom-up.
        for i in (1..self.leaf_count).rev() {
            self.nodes[i] = hash32_concat(&self.nodes[2 * i], &self.nodes[2 * i + 1]);
        }

        self.valid = true;
    }

    /// Get the root (nodes[1] for FixedVector — no mix_in_length).
    fn root(&mut self) -> [u8; 32] {
        let result = self.nodes[1];
        self.last_root = result;
        result
    }
}

static RANDAO_CACHE: LazyLock<Mutex<RandaoMerkleCache>> =
    LazyLock::new(|| Mutex::new(RandaoMerkleCache::new()));

/// Compute the SSZ tree hash root of a FixedVector<Bytes32, EpochsPerHistoricalVector> incrementally.
///
/// On the first call, builds the full tree and caches it.  On subsequent calls, diffs
/// against the cached values and only rehashes affected paths.
#[allow(dead_code)]
pub fn hash_randao_incremental(values: &[[u8; 32]]) -> [u8; 32] {
    let mut cache = RANDAO_CACHE.lock().unwrap();
    if cache.valid && cache.leaf_count >= values.len() {
        // Diff and update only changed leaves.
        let leaf_count = cache.leaf_count;
        for i in 0..values.len() {
            let leaf_idx = leaf_count + i;
            if cache.nodes[leaf_idx] != values[i] {
                cache.nodes[leaf_idx] = values[i];
                // Walk up to root.
                let mut pos = leaf_idx >> 1;
                while pos >= 1 {
                    cache.nodes[pos] =
                        hash32_concat(&cache.nodes[2 * pos], &cache.nodes[2 * pos + 1]);
                    pos >>= 1;
                }
            }
        }
        cache.root()
    } else {
        cache.initialize(values);
        cache.root()
    }
}

/// Seed the cache with known-correct data and hash from the standard SSZ hash path.
/// This allows subsequent `apply_randao_update` calls to work incrementally.
pub fn seed_cache(values: &[[u8; 32]], known_hash: &[u8; 32]) {
    let mut cache = RANDAO_CACHE.lock().unwrap();
    cache.initialize(values);
    cache.last_root = *known_hash;
}

/// Apply a single targeted update and return the new hash.
/// `index` is the position to update, `new_value` is the new 32-byte entry.
/// `expected_prev_hash` validates the cache matches the expected parent state.
///
/// Returns None on cache miss (caller falls back to full hash).
pub fn apply_randao_update(
    index: usize,
    new_value: &[u8; 32],
    total_count: usize,
    expected_prev_hash: &[u8; 32],
) -> Option<[u8; 32]> {
    let mut cache = RANDAO_CACHE.lock().unwrap();
    if !cache.valid || &cache.last_root != expected_prev_hash {
        return None;
    }

    let leaf_count = cache.leaf_count;
    if index >= leaf_count || total_count > leaf_count {
        return None;
    }

    let leaf_idx = leaf_count + index;
    cache.nodes[leaf_idx] = *new_value;

    // Walk up to root.
    let mut pos = leaf_idx >> 1;
    while pos >= 1 {
        cache.nodes[pos] = hash32_concat(&cache.nodes[2 * pos], &cache.nodes[2 * pos + 1]);
        pos >>= 1;
    }

    Some(cache.root())
}

#[cfg(test)]
mod tests {
    use super::*;
    use ethereum_hashing::hash32_concat;

    fn reference_hash(values: &[[u8; 32]]) -> [u8; 32] {
        let leaf_count = values.len().next_power_of_two();
        let mut nodes = vec![[0u8; 32]; 2 * leaf_count];
        for (i, v) in values.iter().enumerate() {
            nodes[leaf_count + i] = *v;
        }
        for i in (1..leaf_count).rev() {
            nodes[i] = hash32_concat(&nodes[2 * i], &nodes[2 * i + 1]);
        }
        nodes[1]
    }

    fn reset_cache() {
        RANDAO_CACHE.lock().unwrap().valid = false;
    }

    #[test]
    fn small_values() {
        reset_cache();
        let mut values = vec![[0u8; 32]; 16];
        values[0] = [1u8; 32];
        values[5] = [42u8; 32];

        let h1 = hash_randao_incremental(&values);
        assert_eq!(h1, reference_hash(&values));
    }

    #[test]
    fn incremental_update() {
        reset_cache();
        let mut values = vec![[0u8; 32]; 64];
        for (i, v) in values.iter_mut().enumerate() {
            v[0] = i as u8;
        }

        let _h1 = hash_randao_incremental(&values);

        // Modify one value.
        values[10] = [255u8; 32];
        let h2 = hash_randao_incremental(&values);
        assert_eq!(h2, reference_hash(&values));
    }

    #[test]
    fn targeted_update() {
        reset_cache();
        let mut values = vec![[0u8; 32]; 32];
        for (i, v) in values.iter_mut().enumerate() {
            v[0] = i as u8;
        }

        let h1 = hash_randao_incremental(&values);

        let new_value = [99u8; 32];
        let h2 = apply_randao_update(10, &new_value, 32, &h1).unwrap();

        values[10] = new_value;
        assert_eq!(h2, reference_hash(&values));
    }

    #[test]
    fn targeted_update_cache_miss() {
        reset_cache();
        let new_value = [99u8; 32];
        let fake_hash = [0u8; 32];
        assert_eq!(apply_randao_update(10, &new_value, 32, &fake_hash), None);
    }
}
