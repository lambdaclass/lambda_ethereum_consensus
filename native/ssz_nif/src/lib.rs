use crate::utils::bytes_to_binary;
use lighthouse_types as lh_types;
use rustler::{Atom, Binary, Decoder, Encoder, Env, NifResult, Term};
use ssz::{Decode, Encode};
use utils::from_lh::FromLH;

mod types;
mod utils;

mod atoms {
    use rustler::atoms;

    atoms! {
        ok,
    }
}

macro_rules! match_schema_and_encode {
    (($schema:expr, $map:expr) => { $($t:tt),* $(,)? }) => {
        match $schema {
            $(
                concat!("Elixir.", stringify!($t)) => encode_ssz::<types::$t, lh_types::$t>($map)?,
            )*
            _ => unreachable!(),
        }
    };
}

macro_rules! match_schema_and_decode {
    (($schema:expr, $bytes:expr, $env:expr) => { $($t:tt),* $(,)? }) => {
        match $schema {
            $(
                concat!("Elixir.", stringify!($t)) => decode_ssz::<types::$t, lh_types::$t>($bytes, $env)?,
            )*
            _ => unreachable!(),
        }
    };
}

fn encode_ssz<'a, Elx, Lh>(value: Term<'a>) -> NifResult<Vec<u8>>
where
    Elx: Decoder<'a> + Into<Lh>,
    Lh: Encode,
{
    let value_nif = <Elx as Decoder>::decode(value)?;
    let value_ssz: Lh = value_nif.into();
    Ok(value_ssz.as_ssz_bytes())
}

fn decode_ssz<'a, Elx, Lh>(bytes: &[u8], env: Env<'a>) -> NifResult<Term<'a>>
where
    Elx: Encoder + FromLH<'a, Lh>,
    Lh: Decode,
{
    let recovered_value = Lh::from_ssz_bytes(bytes).expect("can deserialize");
    let checkpoint = Elx::from(recovered_value, env);
    let term = checkpoint.encode(env);
    Ok(term)
}

#[rustler::nif]
fn to_ssz<'env, 'a>(env: Env<'env>, schema: Atom, map: Term) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string().unwrap();
    let serialized = match_schema_and_encode!(
        (schema.as_str(), map) => {
            Checkpoint,
        }
    );
    Ok((atoms::ok(), bytes_to_binary(env, &serialized)).encode(env))
}

#[rustler::nif]
fn from_ssz<'env>(env: Env<'env>, schema: Atom, bytes: Binary) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string().unwrap();
    let deserialized = match_schema_and_decode!(
        (schema.as_str(), &bytes, env) => {
            Checkpoint,
        }
    );
    Ok((atoms::ok(), deserialized).encode(env))
}

rustler::init!("Elixir.LambdaEthereumConsensus.Ssz", [to_ssz, from_ssz]);
