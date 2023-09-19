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

mod atoms {
    use rustler::atoms;

    atoms! {
        ok,
    }
}

const SCHEMA_PREFIX_SIZE: usize = "Elixir.SszTypes.".len();
const ELIXIR_PREFIX_SIZE: usize = "Elixir.".len();

#[rustler::nif]
fn to_ssz_rs<'env>(env: Env<'env>, map: Term, schema: Atom, config: Atom) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string()?;
    let schema = schema
        .get(SCHEMA_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;
    let config = config.to_term(env).atom_to_string()?;
    let config = config
        .get(ELIXIR_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;

    let serialized = schema_match!(schema, config, encode_ssz, (map));
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
    let config = config
        .get(ELIXIR_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;

    let res = schema_match!(schema, config, decode_ssz, (&bytes, env))?;
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
    let config = config
        .get(ELIXIR_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;

    let res = schema_match!(schema, config, list_decode_ssz, (&bytes, env))?;
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
    let config = config
        .get(ELIXIR_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;

    let serialized = schema_match!(schema, config, hash_tree_root, (map));
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
    let config = config
        .get(ELIXIR_PREFIX_SIZE..)
        .ok_or(rustler::Error::BadArg)?;

    let serialized = schema_match!(schema, config, hash_list_tree_root, (list, max_size));
    Ok((atoms::ok(), bytes_to_binary(env, &serialized?)).encode(env))
}

rustler::init!(
    "Elixir.Ssz",
    [
        to_ssz_rs,
        from_ssz_rs,
        list_from_ssz_rs,
        hash_tree_root_rs,
        hash_tree_root_list_rs
    ]
);
