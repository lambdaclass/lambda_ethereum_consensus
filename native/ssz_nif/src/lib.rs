use crate::utils::helpers::bytes_to_binary;
use lighthouse_types as lh_types;
use rustler::{Atom, Binary, Encoder, Env, NifResult, Term};

mod types;
mod utils;

mod atoms {
    use rustler::atoms;

    atoms! {
        ok,
    }
}

#[rustler::nif]
fn to_ssz<'env, 'a>(env: Env<'env>, schema: Atom, map: Term) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string().unwrap();
    let serialized = match_schema_and_encode!(
        (schema.as_str(), map) => {
            Checkpoint,
            Fork,
        }
    );
    Ok((atoms::ok(), bytes_to_binary(env, &serialized?)).encode(env))
}

#[rustler::nif]
fn from_ssz<'env>(env: Env<'env>, schema: Atom, bytes: Binary) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string().unwrap();
    let deserialized = match_schema_and_decode!(
        (schema.as_str(), &bytes, env) => {
            Checkpoint,
            Fork,
        }
    );
    Ok((atoms::ok(), deserialized?).encode(env))
}

rustler::init!("Elixir.LambdaEthereumConsensus.Ssz", [to_ssz, from_ssz]);
