use lighthouse_types::Checkpoint;
use rustler::{Env, Binary};
use ssz::{Encode, Decode};
use crate::{types::checkpoint::CheckpointNif, utils::bytes_to_binary};

mod types;
mod utils;

#[rustler::nif]
fn to_ssz<'env>(env: Env<'env>, value_nif: CheckpointNif) -> Result<Binary<'env>, String> {
    let value_ssz: Checkpoint = value_nif.clone().into();
    let serialized = value_ssz.as_ssz_bytes();
    Ok(bytes_to_binary(env, &serialized))
}

#[rustler::nif]
fn from_ssz<'env>(env: Env<'env>, bytes: Binary) -> Result<CheckpointNif<'env>, String> {
    let recovered_value = Checkpoint::from_ssz_bytes(&bytes).expect("can deserialize");
    let checkpoint = CheckpointNif::from(recovered_value, env);

    return Ok(checkpoint);
}

rustler::init!("Elixir.LambdaEthereumConsensus.Ssz", [to_ssz, from_ssz]);
