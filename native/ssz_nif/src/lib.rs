//! # SSZ NIF
//!
//! To add a new type:
//!  - Add the type to the [`elx_types`] and [`ssz_types`] modules, using the [`gen_struct`](utils::gen_struct) macro
//!  - Implement the necessary traits ([`FromElx`](utils::from_elx::FromElx) and [`FromSsz`](utils::from_ssz::FromSsz)) for its attributes
//!  - Add the type to [`to_ssz_rs`] and [`from_ssz_rs`] "match" macros

pub(crate) mod elx_types;
pub(crate) mod ssz_types;
pub(crate) mod utils;

use crate::utils::{helpers::bytes_to_binary, schema_match};
use rustler::{Atom, Binary, Encoder, Env, NifResult, Term};
use std::collections::HashMap;

mod atoms {
    use rustler::atoms;

    atoms! {
        ok,
    }
}

const SCHEMA_PREFIX_SIZE: usize = "Elixir.Types.".len();

#[rustler::nif]
fn to_ssz_rs<'env>(env: Env<'env>, map: Term, schema: Atom, config: Atom) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string()?;
    let schema = schema
        .get(SCHEMA_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;
    let config = config.to_term(env).atom_to_string()?;

    let serialized = schema_match!(schema, config.as_str(), encode_ssz, (map));
    Ok((atoms::ok(), bytes_to_binary(env, &serialized?)).encode(env))
}

#[rustler::nif]
fn from_ssz_rs<'env>(
    env: Env<'env>,
    bytes: Binary,
    schema: Atom,
    config: Atom,
) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string()?;
    let schema = schema
        .get(SCHEMA_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;
    let config = config.to_term(env).atom_to_string()?;

    let res = schema_match!(schema, config.as_str(), decode_ssz, (&bytes, env))?;
    Ok((atoms::ok(), res).encode(env))
}

#[rustler::nif]
fn list_from_ssz_rs<'env>(
    env: Env<'env>,
    bytes: Binary,
    schema: Atom,
    config: Atom,
) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string()?;
    let schema = schema
        .get(SCHEMA_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;
    let config = config.to_term(env).atom_to_string()?;

    let res = schema_match!(schema, config.as_str(), list_decode_ssz, (&bytes, env))?;
    Ok((atoms::ok(), res).encode(env))
}

#[rustler::nif]
fn hash_tree_root_rs<'env>(
    env: Env<'env>,
    map: Term,
    schema: Atom,
    config: Atom,
) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string()?;
    let schema = schema
        .get(SCHEMA_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;
    let config = config.to_term(env).atom_to_string()?;

    let serialized = schema_match!(schema, config.as_str(), hash_tree_root, (map));
    Ok((atoms::ok(), bytes_to_binary(env, &serialized?)).encode(env))
}

#[rustler::nif]
fn hash_tree_root_list_rs<'env>(
    env: Env<'env>,
    list: Vec<Term>,
    max_size: usize,
    schema: Atom,
    config: Atom,
) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string()?;
    let schema = schema
        .get(SCHEMA_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;
    let config = config.to_term(env).atom_to_string()?;

    let serialized = schema_match!(
        schema,
        config.as_str(),
        hash_list_tree_root,
        (list, max_size)
    );
    Ok((atoms::ok(), bytes_to_binary(env, &serialized?)).encode(env))
}

#[rustler::nif]
fn hash_tree_root_vector_rs<'env>(
    env: Env<'env>,
    list: Vec<Term>,
    max_size: usize,
    schema: Atom,
    config: Atom,
) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string()?;
    let schema = schema
        .get(SCHEMA_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;
    let config = config.to_term(env).atom_to_string()?;

    let serialized = schema_match!(
        schema,
        config.as_str(),
        hash_vector_tree_root,
        (list, max_size)
    );
    Ok((atoms::ok(), bytes_to_binary(env, &serialized?)).encode(env))
}

/// Parse a map of {u32 => Binary} into a HashMap of {u32 => [u8; 32]}.
fn decode_cached_hashes(cached_hashes_map: Term) -> NifResult<HashMap<u32, [u8; 32]>> {
    let cached_raw: HashMap<u32, Binary> = cached_hashes_map.decode()?;
    let mut cached: HashMap<u32, [u8; 32]> = HashMap::with_capacity(cached_raw.len());
    for (k, v) in cached_raw {
        let arr: [u8; 32] = v
            .as_slice()
            .try_into()
            .map_err(|_| rustler::Error::BadArg)?;
        cached.insert(k, arr);
    }
    Ok(cached)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn hash_beacon_state_cached_rs<'a>(
    env: Env<'a>,
    state: Term<'a>,
    cached_hashes_map: Term<'a>,
    config: Atom,
) -> NifResult<Term<'a>> {
    let config_str = config.to_term(env).atom_to_string()?;
    let cached = decode_cached_hashes(cached_hashes_map)?;

    let result = match config_str.as_str() {
        "mainnet" => crate::utils::cached_hash::hash_beacon_state_cached::<
            crate::ssz_types::config::Mainnet,
        >(env, state, &cached)?,
        "minimal" => crate::utils::cached_hash::hash_beacon_state_cached::<
            crate::ssz_types::config::Minimal,
        >(env, state, &cached)?,
        "gnosis" => crate::utils::cached_hash::hash_beacon_state_cached::<
            crate::ssz_types::config::Gnosis,
        >(env, state, &cached)?,
        _ => return Err(rustler::Error::BadArg),
    };

    Ok((
        atoms::ok(),
        bytes_to_binary(env, &result.root),
        bytes_to_binary(env, &result.field_hashes),
    )
        .encode(env))
}

/// Apply targeted balance updates to the cached incremental balance merkle tree.
/// Returns `{:ok, hash}` if the cache is valid, or `{:error, :cache_miss}` if the cache
/// needs to be rebuilt (caller should fall through to the full hash path).
///
/// `updates` is a list of `{index :: u32, new_value :: u64}` tuples.
/// `balance_count` is the current total number of balances (for mix_in_length).
#[rustler::nif(schedule = "DirtyCpu")]
fn update_balance_cache_rs<'a>(
    env: Env<'a>,
    updates: Vec<(u32, u64)>,
    balance_count: u64,
    expected_prev_hash: Binary<'a>,
) -> NifResult<Term<'a>> {
    let prev_hash: &[u8; 32] = expected_prev_hash
        .as_slice()
        .try_into()
        .map_err(|_| rustler::Error::BadArg)?;
    match crate::utils::balance_cache::apply_updates_and_hash(
        &updates,
        balance_count as usize,
        prev_hash,
    ) {
        Some(hash) => Ok((atoms::ok(), bytes_to_binary(env, &hash)).encode(env)),
        None => {
            let error_atom = Atom::from_str(env, "error")?;
            let miss_atom = Atom::from_str(env, "cache_miss")?;
            Ok((error_atom, miss_atom).encode(env))
        }
    }
}

/// Apply targeted participation updates to the cached incremental participation merkle tree.
/// Returns `{:ok, hash}` if the cache is valid, or `{:error, :cache_miss}` if the cache
/// needs to be rebuilt (caller should fall through to the full hash path).
///
/// `field_num` is 15 (previous_epoch_participation) or 16 (current_epoch_participation).
/// `updates` is a list of `{index :: u32, new_value :: u8}` tuples.
/// `value_count` is the current total number of participation entries (for mix_in_length).
#[rustler::nif(schedule = "DirtyCpu")]
fn update_participation_cache_rs<'a>(
    env: Env<'a>,
    field_num: u32,
    updates: Vec<(u32, u8)>,
    value_count: u64,
    expected_prev_hash: Binary<'a>,
) -> NifResult<Term<'a>> {
    let prev_hash: &[u8; 32] = expected_prev_hash
        .as_slice()
        .try_into()
        .map_err(|_| rustler::Error::BadArg)?;
    match crate::utils::participation_cache::apply_participation_updates(
        field_num,
        &updates,
        value_count as usize,
        prev_hash,
    ) {
        Some(hash) => Ok((atoms::ok(), bytes_to_binary(env, &hash)).encode(env)),
        None => {
            let error_atom = Atom::from_str(env, "error")?;
            let miss_atom = Atom::from_str(env, "cache_miss")?;
            Ok((error_atom, miss_atom).encode(env))
        }
    }
}

/// Apply a single targeted randao_mixes update to the cached incremental merkle tree.
/// Returns `{:ok, hash}` if the cache is valid, or `{:error, :cache_miss}` on miss.
///
/// `index` is the position to update, `new_value` is the new 32-byte entry.
/// `total_count` is the total number of randao mix entries.
/// `expected_prev_hash` validates the cache matches the expected parent state.
#[rustler::nif(schedule = "DirtyCpu")]
fn update_randao_cache_rs<'a>(
    env: Env<'a>,
    index: u64,
    new_value: Binary<'a>,
    total_count: u64,
    expected_prev_hash: Binary<'a>,
) -> NifResult<Term<'a>> {
    let value: &[u8; 32] = new_value
        .as_slice()
        .try_into()
        .map_err(|_| rustler::Error::BadArg)?;
    let prev_hash: &[u8; 32] = expected_prev_hash
        .as_slice()
        .try_into()
        .map_err(|_| rustler::Error::BadArg)?;
    match crate::utils::randao_cache::apply_randao_update(
        index as usize,
        value,
        total_count as usize,
        prev_hash,
    ) {
        Some(hash) => Ok((atoms::ok(), bytes_to_binary(env, &hash)).encode(env)),
        None => {
            let error_atom = Atom::from_str(env, "error")?;
            let miss_atom = Atom::from_str(env, "cache_miss")?;
            Ok((error_atom, miss_atom).encode(env))
        }
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn compute_proposer_indices_rs(
    epoch_seed: Binary,
    start_slot: u64,
    slots_per_epoch: u32,
    active_indices: Vec<u64>,
    effective_balances: Vec<u64>,
    max_effective_balance: u64,
    rounds: u32,
) -> NifResult<Vec<u64>> {
    if epoch_seed.len() != 32 {
        return Err(rustler::Error::BadArg);
    }
    let seed: &[u8; 32] = epoch_seed
        .as_slice()
        .try_into()
        .map_err(|_| rustler::Error::BadArg)?;
    Ok(crate::utils::shuffle::compute_proposer_indices(
        seed,
        start_slot,
        slots_per_epoch,
        &active_indices,
        &effective_balances,
        max_effective_balance,
        rounds,
    ))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn shuffle_list_rs<'env>(
    env: Env<'env>,
    indices: Vec<u64>,
    seed: Binary,
    rounds: u32,
) -> NifResult<Vec<u64>> {
    if seed.len() != 32 {
        return Err(rustler::Error::BadArg);
    }
    let seed_arr: &[u8; 32] = seed
        .as_slice()
        .try_into()
        .map_err(|_| rustler::Error::BadArg)?;
    let mut arr = indices;
    crate::utils::shuffle::shuffle_list(&mut arr, seed_arr, rounds);
    Ok(arr)
}

rustler::init!(
    "Elixir.Ssz",
    [
        to_ssz_rs,
        from_ssz_rs,
        list_from_ssz_rs,
        hash_tree_root_rs,
        hash_tree_root_list_rs,
        hash_tree_root_vector_rs,
        hash_beacon_state_cached_rs,
        update_balance_cache_rs,
        update_participation_cache_rs,
        update_randao_cache_rs,
        shuffle_list_rs,
        compute_proposer_indices_rs,
    ]
);
