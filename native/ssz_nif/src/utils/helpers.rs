use crate::utils::from_ssz::FromSsz;
use rustler::{Binary, Decoder, Encoder, Env, NewBinary, NifResult, Term};
use ssz::{Decode, Encode};
use std::io::Write;

use super::from_elx::{FromElx, FromElxError};

pub(crate) fn bytes_to_binary<'env>(env: Env<'env>, bytes: &[u8]) -> Binary<'env> {
    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(bytes).unwrap();
    binary.into()
}

pub(crate) fn encode_ssz<'a, Elx, Ssz>(value: Term<'a>) -> NifResult<Vec<u8>>
where
    Elx: Decoder<'a>,
    Ssz: Encode + FromElx<Elx>,
{
    let value_nif = <Elx as Decoder>::decode(value)?;
    let value_ssz = Ssz::from(value_nif).map_err(to_nif_result)?;
    Ok(value_ssz.as_ssz_bytes())
}

fn to_nif_result(result: FromElxError) -> rustler::Error {
    rustler::Error::Term(Box::new(result.to_string()))
}

pub(crate) fn decode_ssz<'a, Elx, Ssz>(bytes: &[u8], env: Env<'a>) -> Result<Term<'a>, String>
where
    Elx: Encoder + FromSsz<'a, Ssz>,
    Ssz: Decode,
{
    let recovered_value = Ssz::from_ssz_bytes(bytes).map_err(|e| format!("{e:?}"))?;
    let checkpoint = Elx::from(recovered_value, env);
    Ok(checkpoint.encode(env))
}
