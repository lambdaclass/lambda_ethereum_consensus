use sha2::{Digest, Sha256};

/// Perform the full eth2 shuffle in Rust with O(1) array access.
/// This replaces the Elixir implementation that uses :atomics + Enum.reduce.
///
/// Algorithm: eth2 spec `compute_shuffled_index` applied as a full Fisher-Yates
/// shuffle over all indices, using the swap-or-not network.
pub fn shuffle_list(indices: &mut [u64], seed: &[u8; 32], rounds: u32) {
    let n = indices.len();
    if n <= 1 {
        return;
    }

    for round in (0..rounds).rev() {
        let round_byte = round as u8;

        // Compute pivot = hash(seed || round_byte) mod n
        let pivot = {
            let mut hasher = Sha256::new();
            hasher.update(seed);
            hasher.update([round_byte]);
            let hash = hasher.finalize();
            u64::from_le_bytes(hash[..8].try_into().unwrap()) % (n as u64)
        } as usize;

        // First half: i in [0, mirror)
        let mirror = (pivot + 1) / 2;
        let mut source = {
            let pos_bytes = ((pivot / 256) as u32).to_le_bytes();
            let mut hasher = Sha256::new();
            hasher.update(seed);
            hasher.update([round_byte]);
            hasher.update(pos_bytes);
            hasher.finalize().to_vec()
        };
        let mut byte_v = source[(pivot & 0xFF) / 8];

        for i in 0..mirror {
            let j = pivot - i;

            // Update source hash when crossing a 256-boundary
            if (j & 0xFF) == 0xFF {
                let pos_bytes = ((j / 256) as u32).to_le_bytes();
                let mut hasher = Sha256::new();
                hasher.update(seed);
                hasher.update([round_byte]);
                hasher.update(pos_bytes);
                source = hasher.finalize().to_vec();
            }

            // Update byte_v when crossing an 8-boundary
            if (j & 0x07) == 0x07 {
                byte_v = source[(j & 0xFF) / 8];
            }

            // Check the bit
            let bit = (byte_v >> (j & 0x07)) & 0x01;
            if bit == 1 {
                indices.swap(i, j);
            }
        }

        // Second half: i in [pivot+1, mirror2)
        let mirror2 = (pivot + n + 1) / 2;
        let list_end = n - 1;
        source = {
            let pos_bytes = ((list_end / 256) as u32).to_le_bytes();
            let mut hasher = Sha256::new();
            hasher.update(seed);
            hasher.update([round_byte]);
            hasher.update(pos_bytes);
            hasher.finalize().to_vec()
        };
        byte_v = source[(list_end & 0xFF) / 8];

        for i in (pivot + 1)..mirror2 {
            let loop_iter = i - (pivot + 1);
            let j = list_end - loop_iter;

            if (j & 0xFF) == 0xFF {
                let pos_bytes = ((j / 256) as u32).to_le_bytes();
                let mut hasher = Sha256::new();
                hasher.update(seed);
                hasher.update([round_byte]);
                hasher.update(pos_bytes);
                source = hasher.finalize().to_vec();
            }

            if (j & 0x07) == 0x07 {
                byte_v = source[(j & 0xFF) / 8];
            }

            let bit = (byte_v >> (j & 0x07)) & 0x01;
            if bit == 1 {
                indices.swap(i, j);
            }
        }
    }
}
