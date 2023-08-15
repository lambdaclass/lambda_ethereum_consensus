use crate::utils::bytes_to_binary;
use lighthouse_types as lh_types;
use rustler::{Atom, Binary, Decoder, Encoder, Env, NifResult, Term};
use ssz::{Decode, Encode};

mod types;
mod utils;

mod atoms {
    use rustler::atoms;

    atoms! {
        ok,
    }
}

macro_rules! match_schema {
    (($schema:expr, $map:expr) => { $($t:tt),* $(,)? }) => {
        match $schema {
            $(
                concat!("Elixir.", stringify!($t)) => encode_ssz::<types::$t, lh_types::$t>($map)?,
            )*
            _ => unreachable!(),
        }
    };
}

fn encode_ssz<'a, T, U>(value: Term<'a>) -> NifResult<Vec<u8>>
where
    T: Decoder<'a> + Into<U>,
    U: Encode,
{
    let value_nif = <T as Decoder>::decode(value)?;
    let value_ssz: U = value_nif.into();
    Ok(value_ssz.as_ssz_bytes())
}

#[rustler::nif]
fn to_ssz<'env, 'a>(env: Env<'env>, schema: Atom, map: Term) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string().unwrap();
    let serialized = match_schema!(
        (schema.as_str(), map) => {
            Checkpoint,
        }
    );
    Ok((atoms::ok(), bytes_to_binary(env, &serialized)).encode(env))
}

#[rustler::nif]
fn from_ssz<'env>(env: Env<'env>, bytes: Binary) -> NifResult<Term<'env>> {
    let recovered_value = lh_types::Checkpoint::from_ssz_bytes(&bytes).expect("can deserialize");
    let checkpoint = types::Checkpoint::from(recovered_value, env);

    return Ok((atoms::ok(), checkpoint).encode(env));
}

rustler::init!("Elixir.LambdaEthereumConsensus.Ssz", [to_ssz, from_ssz]);
