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
    ]
);
