use rustler::{Atom, Binary, Decoder, Env, NifResult, Term};
use std::collections::HashMap;
use tree_hash::{MerkleHasher, TreeHash};

use crate::ssz_types::config::Config;
use crate::utils::from_elx::{FromElx, FromElxError};

use ssz::Decode;

/// Helper to convert a field from Elixir Term to SSZ type and hash it.
fn convert_and_hash<'a, Elx, Ssz>(field_term: Term<'a>) -> NifResult<[u8; 32]>
where
    Elx: Decoder<'a>,
    Ssz: TreeHash + FromElx<Elx>,
{
    let elx_val = Elx::decode(field_term)?;
    let ssz_val = Ssz::from(elx_val)
        .map_err(|e: FromElxError| rustler::Error::Term(Box::new(e.to_string())))?;
    Ok(ssz_val.tree_hash_root().0)
}

/// Helper to convert a Vec field and compute its tree hash root as a VariableList.
fn convert_and_hash_list<'a, Elx, Ssz, N>(field_term: Term<'a>) -> NifResult<[u8; 32]>
where
    Elx: Decoder<'a>,
    Ssz: TreeHash + FromElx<Elx>,
    N: ssz_types::typenum::Unsigned,
{
    let elx_vec: Vec<Elx> = Decoder::decode(field_term)?;
    let ssz_vec: Vec<Ssz> = elx_vec
        .into_iter()
        .map(FromElx::from)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e: FromElxError| rustler::Error::Term(Box::new(e.to_string())))?;
    let list = ssz_types::VariableList::<Ssz, N>::new(ssz_vec)
        .map_err(|e| rustler::Error::Term(Box::new(format!("{e:?}"))))?;
    Ok(list.tree_hash_root().0)
}

/// Helper to convert a Vec field and compute its tree hash root as a FixedVector.
fn convert_and_hash_vector<'a, Elx, Ssz, N>(field_term: Term<'a>) -> NifResult<[u8; 32]>
where
    Elx: Decoder<'a>,
    Ssz: TreeHash + FromElx<Elx>,
    N: ssz_types::typenum::Unsigned,
{
    let elx_vec: Vec<Elx> = Decoder::decode(field_term)?;
    let ssz_vec: Vec<Ssz> = elx_vec
        .into_iter()
        .map(FromElx::from)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e: FromElxError| rustler::Error::Term(Box::new(e.to_string())))?;
    let vector = ssz_types::FixedVector::<Ssz, N>::new(ssz_vec)
        .map_err(|e| rustler::Error::Term(Box::new(format!("{e:?}"))))?;
    Ok(vector.tree_hash_root().0)
}

/// Helper to convert a Binary field (BitVector) and hash it.
fn convert_and_hash_bitvector<'a, N>(field_term: Term<'a>) -> NifResult<[u8; 32]>
where
    N: ssz_types::typenum::Unsigned,
{
    let bin = Binary::from_term(field_term)?;
    let bv = ssz_types::BitVector::<N>::from_ssz_bytes(&bin)
        .map_err(|e| rustler::Error::Term(Box::new(format!("{e:?}"))))?;
    Ok(bv.tree_hash_root().0)
}

/// Get a field from an Elixir struct by atom name.
fn get_field<'a>(env: Env<'a>, state: Term<'a>, field_name: &str) -> NifResult<Term<'a>> {
    let atom = Atom::from_str(env, field_name)?;
    state.map_get(atom.to_term(env))
}

/// Result of hash_beacon_state_cached: the root hash and all individual field hashes.
pub(crate) struct CachedHashResult {
    pub root: [u8; 32],
    /// All field hashes concatenated: field_count * 32 bytes
    pub field_hashes: Vec<u8>,
}

/// Hash a BeaconState with cached field hashes.
/// `cached_hashes` maps field index (0-based) to pre-computed 32-byte hash.
/// Fields not in the cache are computed from the state.
/// Returns the root hash and all individual field hashes (for caching by the caller).
pub(crate) fn hash_beacon_state_cached<'a, C: Config>(
    env: Env<'a>,
    state: Term<'a>,
    cached_hashes: &HashMap<u32, [u8; 32]>,
) -> NifResult<CachedHashResult> {
    // BeaconState fields in schema order (must match Rust struct AND Elixir schema)
    let field_names: &[&str] = &[
        "genesis_time",                     // 0
        "genesis_validators_root",          // 1
        "slot",                             // 2
        "fork",                             // 3
        "latest_block_header",              // 4
        "block_roots",                      // 5
        "state_roots",                      // 6
        "historical_roots",                 // 7
        "eth1_data",                        // 8
        "eth1_data_votes",                  // 9
        "eth1_deposit_index",               // 10
        "validators",                       // 11
        "balances",                         // 12
        "randao_mixes",                     // 13
        "slashings",                        // 14
        "previous_epoch_participation",     // 15
        "current_epoch_participation",      // 16
        "justification_bits",               // 17
        "previous_justified_checkpoint",    // 18
        "current_justified_checkpoint",     // 19
        "finalized_checkpoint",             // 20
        "inactivity_scores",                // 21
        "current_sync_committee",           // 22
        "next_sync_committee",              // 23
        "latest_execution_payload_header",  // 24
        "next_withdrawal_index",            // 25
        "next_withdrawal_validator_index",  // 26
        "historical_summaries",             // 27
        "deposit_requests_start_index",     // 28
        "deposit_balance_to_consume",       // 29
        "exit_balance_to_consume",          // 30
        "earliest_exit_epoch",              // 31
        "consolidation_balance_to_consume", // 32
        "earliest_consolidation_epoch",     // 33
        "pending_deposits",                 // 34
        "pending_partial_withdrawals",      // 35
        "pending_consolidations",           // 36
        "proposer_lookahead",               // 37
    ];

    let num_fields = field_names.len();
    let mut hasher = MerkleHasher::with_leaves(num_fields);
    let mut all_field_hashes: Vec<u8> = Vec::with_capacity(num_fields * 32);

    for (idx, &name) in field_names.iter().enumerate() {
        let hash = if let Some(cached) = cached_hashes.get(&(idx as u32)) {
            *cached
        } else {
            let field = get_field(env, state, name)?;
            compute_field_hash::<C>(idx, field)?
        };
        all_field_hashes.extend_from_slice(&hash);
        hasher
            .write(&hash)
            .map_err(|e| rustler::Error::Term(Box::new(format!("{e:?}"))))?;
    }

    let root = hasher
        .finish()
        .map_err(|e| rustler::Error::Term(Box::new(format!("{e:?}"))))?;
    Ok(CachedHashResult {
        root: root.0,
        field_hashes: all_field_hashes,
    })
}

/// Compute the tree hash of a single BeaconState field by index.
fn compute_field_hash<'a, C: Config>(field_index: usize, field: Term<'a>) -> NifResult<[u8; 32]> {
    use crate::elx_types;
    use crate::ssz_types;

    match field_index {
        // Scalar u64 fields
        0 | 2 | 10 | 25 | 26 | 28 | 29 | 30 | 31 | 32 | 33 => {
            let val: u64 = field.decode()?;
            Ok(val.tree_hash_root().0)
        }
        // Root (Bytes32) field: genesis_validators_root
        1 => {
            let bin = Binary::from_term(field)?;
            let arr: [u8; 32] = bin
                .as_slice()
                .try_into()
                .map_err(|_| rustler::Error::BadArg)?;
            Ok(arr.tree_hash_root().0)
        }
        // Fork
        3 => convert_and_hash::<elx_types::Fork, ssz_types::Fork>(field),
        // BeaconBlockHeader
        4 => convert_and_hash::<elx_types::BeaconBlockHeader, ssz_types::BeaconBlockHeader>(field),
        // block_roots: FixedVector<Root, SlotsPerHistoricalRoot>
        5 => convert_and_hash_vector::<Binary, [u8; 32], C::SlotsPerHistoricalRoot>(field),
        // state_roots: FixedVector<Root, SlotsPerHistoricalRoot>
        6 => convert_and_hash_vector::<Binary, [u8; 32], C::SlotsPerHistoricalRoot>(field),
        // historical_roots: VariableList<Root, HistoricalRootsLimit>
        7 => convert_and_hash_list::<Binary, [u8; 32], C::HistoricalRootsLimit>(field),
        // eth1_data
        8 => convert_and_hash::<elx_types::Eth1Data, ssz_types::Eth1Data>(field),
        // eth1_data_votes: VariableList<Eth1Data>
        9 => convert_and_hash_list::<
            elx_types::Eth1Data,
            ssz_types::Eth1Data,
            C::SlotsPerEth1VotingPeriod,
        >(field),
        // validators: VariableList<Validator, ValidatorRegistryLimit>
        11 => convert_and_hash_list::<
            elx_types::Validator,
            ssz_types::Validator,
            C::ValidatorRegistryLimit,
        >(field),
        // balances: VariableList<u64, ValidatorRegistryLimit>
        // Use incremental merkle cache: decode the Vec<u64> and hand it to the
        // balance cache which diffs against its previous state and only rehashes
        // the changed chunks.
        12 => {
            let balances: Vec<u64> = Decoder::decode(field)?;
            Ok(crate::utils::balance_cache::hash_balances_incremental(
                &balances,
            ))
        }
        // randao_mixes: FixedVector<Bytes32, EpochsPerHistoricalVector>
        // Decode once, compute standard SSZ hash, and seed the incremental cache
        // so that subsequent Elixir-side targeted updates can skip this conversion.
        13 => {
            let binaries: Vec<Binary> = Decoder::decode(field)?;
            let ssz_vec: Vec<[u8; 32]> = binaries
                .into_iter()
                .map(|b| FromElx::from(b))
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e: FromElxError| rustler::Error::Term(Box::new(e.to_string())))?;
            let vector =
                ::ssz_types::FixedVector::<[u8; 32], C::EpochsPerHistoricalVector>::new(
                    ssz_vec.clone(),
                )
                .map_err(|e| rustler::Error::Term(Box::new(format!("{e:?}"))))?;
            let result = vector.tree_hash_root().0;
            // Seed the cache so targeted updates work on subsequent blocks.
            crate::utils::randao_cache::seed_cache(&ssz_vec, &result);
            Ok(result)
        }
        // slashings: FixedVector<u64, EpochsPerSlashingsVector>
        14 => convert_and_hash_vector::<u64, u64, C::EpochsPerSlashingsVector>(field),
        // previous_epoch_participation: VariableList<u8, ValidatorRegistryLimit>
        // Use incremental merkle cache: decode the Vec<u8> and hand it to the
        // participation cache which diffs against its previous state.
        15 => {
            let values: Vec<u8> = Decoder::decode(field)?;
            Ok(crate::utils::participation_cache::hash_participation_incremental(15, &values))
        }
        // current_epoch_participation: VariableList<u8, ValidatorRegistryLimit>
        16 => {
            let values: Vec<u8> = Decoder::decode(field)?;
            Ok(crate::utils::participation_cache::hash_participation_incremental(16, &values))
        }
        // justification_bits: BitVector
        17 => convert_and_hash_bitvector::<C::JustificationBitsLength>(field),
        // Checkpoints
        18 | 19 | 20 => convert_and_hash::<elx_types::Checkpoint, ssz_types::Checkpoint>(field),
        // inactivity_scores: VariableList<u64, ValidatorRegistryLimit>
        21 => convert_and_hash_list::<u64, u64, C::ValidatorRegistryLimit>(field),
        // current_sync_committee
        22 => convert_and_hash::<elx_types::SyncCommittee, ssz_types::SyncCommittee<C>>(field),
        // next_sync_committee
        23 => convert_and_hash::<elx_types::SyncCommittee, ssz_types::SyncCommittee<C>>(field),
        // latest_execution_payload_header
        24 => convert_and_hash::<
            elx_types::ExecutionPayloadHeader,
            ssz_types::ExecutionPayloadHeader<C>,
        >(field),
        // historical_summaries: VariableList<HistoricalSummary, HistoricalRootsLimit>
        27 => convert_and_hash_list::<
            elx_types::HistoricalSummary,
            ssz_types::HistoricalSummary,
            C::HistoricalRootsLimit,
        >(field),
        // pending_deposits: VariableList<PendingDeposit, PendingDepositsLimit>
        34 => convert_and_hash_list::<
            elx_types::PendingDeposit,
            ssz_types::PendingDeposit,
            C::PendingDepositsLimit,
        >(field),
        // pending_partial_withdrawals
        35 => convert_and_hash_list::<
            elx_types::PendingPartialWithdrawal,
            ssz_types::PendingPartialWithdrawal,
            C::PendingPartialWithdrawalsLimit,
        >(field),
        // pending_consolidations
        36 => convert_and_hash_list::<
            elx_types::PendingConsolidation,
            ssz_types::PendingConsolidation,
            C::PendingConsolidationsLimit,
        >(field),
        // proposer_lookahead: FixedVector<u64, ProposerLookaheadLength>
        37 => convert_and_hash_vector::<u64, u64, C::ProposerLookaheadLength>(field),

        _ => Err(rustler::Error::Term(Box::new(format!(
            "Unknown field index: {field_index}"
        )))),
    }
}
