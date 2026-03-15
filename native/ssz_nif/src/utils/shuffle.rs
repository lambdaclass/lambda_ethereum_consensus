use sha2::{Digest, Sha256};

fn sha256(data: &[u8]) -> Vec<u8> {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().to_vec()
}

/// Compute the shuffled index for a single position (eth2 spec compute_shuffled_index).
pub fn compute_shuffled_index(
    mut index: u64,
    index_count: u64,
    seed: &[u8; 32],
    rounds: u32,
) -> u64 {
    if index_count == 0 {
        return index;
    }
    for round in 0..rounds {
        let round_byte = round as u8;
        let mut buf = Vec::with_capacity(33);
        buf.extend_from_slice(seed);
        buf.push(round_byte);
        let pivot_hash = sha256(&buf);
        let pivot = u64::from_le_bytes(pivot_hash[..8].try_into().unwrap()) % index_count;

        let flip = (pivot + index_count - index) % index_count;
        let position = std::cmp::max(index, flip);

        let pos_div_256 = (position / 256) as u32;
        let mut buf2 = Vec::with_capacity(37);
        buf2.extend_from_slice(seed);
        buf2.push(round_byte);
        buf2.extend_from_slice(&pos_div_256.to_le_bytes());
        let source = sha256(&buf2);

        let bit_index = (position % 256) as usize;
        let byte_val = source[bit_index / 8];
        let bit = (byte_val >> (bit_index % 8)) & 1;

        if bit == 1 {
            index = flip;
        }
    }
    index
}

/// Batch compute proposer indices for all slots in an epoch.
/// For each slot, finds the first candidate whose effective balance passes
/// the random threshold. This replaces ~2048 individual Elixir NIF calls.
pub fn compute_proposer_indices(
    epoch_seed: &[u8; 32],
    start_slot: u64,
    slots_per_epoch: u32,
    active_indices: &[u64],
    effective_balances: &[u64],
    max_effective_balance: u64,
    rounds: u32,
) -> Vec<u64> {
    let total = active_indices.len() as u64;
    let max_random: u64 = 0xFFFF; // 2^16 - 1

    (0..slots_per_epoch)
        .map(|i| {
            // Per-slot seed
            let slot = start_slot + i as u64;
            let mut slot_seed_input = Vec::with_capacity(40);
            slot_seed_input.extend_from_slice(epoch_seed);
            slot_seed_input.extend_from_slice(&slot.to_le_bytes());
            let slot_seed_vec = sha256(&slot_seed_input);
            let slot_seed: [u8; 32] = slot_seed_vec[..32].try_into().unwrap();

            // Find proposer
            let mut candidate_iter = 0u64;
            loop {
                let shuffled =
                    compute_shuffled_index(candidate_iter % total, total, &slot_seed, rounds);
                let candidate_index = active_indices[shuffled as usize];

                // Random bytes
                let mut rand_input = Vec::with_capacity(40);
                rand_input.extend_from_slice(&slot_seed);
                rand_input.extend_from_slice(&(candidate_iter / 16).to_le_bytes());
                let random_bytes = sha256(&rand_input);
                let offset = ((candidate_iter % 16) * 2) as usize;
                let random_value =
                    u16::from_le_bytes([random_bytes[offset], random_bytes[offset + 1]]) as u64;

                let eff_bal = effective_balances[candidate_index as usize];

                if eff_bal * max_random >= max_effective_balance * random_value {
                    break candidate_index;
                }
                candidate_iter += 1;
            }
        })
        .collect()
}

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
