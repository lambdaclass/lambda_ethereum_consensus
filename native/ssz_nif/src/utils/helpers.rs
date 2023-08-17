use crate::utils::from_lh::FromLH;
use rustler::{Binary, Decoder, Encoder, Env, NewBinary, NifResult, Term};
use ssz::{Decode, Encode};
use std::io::Write;

use super::from_elx::FromElx;

pub(crate) fn bytes_to_binary<'env>(env: Env<'env>, bytes: &[u8]) -> Binary<'env> {
    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(bytes).unwrap();
    binary.into()
}

pub(crate) fn encode_ssz<'a, Elx, Lh>(value: Term<'a>) -> NifResult<Vec<u8>>
where
    Elx: Decoder<'a>,
    Lh: Encode + FromElx<Elx>,
{
    let value_nif = <Elx as Decoder>::decode(value)?;
    let value_ssz = Lh::from(value_nif);
    Ok(value_ssz.as_ssz_bytes())
}

pub(crate) fn decode_ssz<'a, Elx, Lh>(bytes: &[u8], env: Env<'a>) -> Term<'a>
where
    Elx: Encoder + FromLH<'a, Lh>,
    Lh: Decode,
{
    let recovered_value = Lh::from_ssz_bytes(bytes).expect("can deserialize");
    let checkpoint = Elx::from(recovered_value, env);
    checkpoint.encode(env)
}
