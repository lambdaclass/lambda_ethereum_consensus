//! # SSZ NIF
//!
//! To add a new type:
//!  - Add the type to the [`elx_types`] and [`ssz_types`] modules, using the [`gen_struct`](utils::gen_struct) macro
//!  - Implement the necessary traits ([`FromElx`](utils::from_elx::FromElx) and [`FromSsz`](utils::from_ssz::FromSsz)) for its attributes
//!  - Add the type to [`to_ssz_rs`] and [`from_ssz_rs`] "match" macros

pub(crate) mod elx_types;
pub(crate) mod ssz_types;
pub(crate) mod utils;

use crate::utils::{
    helpers::bytes_to_binary, match_schema_and_decode, match_schema_and_encode,
    match_schema_and_hash,
};
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

    let serialized = match_schema_and_encode!(
        (schema, config, map) => {
            HistoricalSummary,
            AttestationData,
            IndexedAttestation<C>,
            Checkpoint,
            Eth1Data,
            Fork,
            ForkData,
            HistoricalBatch<C>,
            PendingAttestation<C>,
            Validator,
            DepositData,
            VoluntaryExit,
            Deposit,
            DepositMessage,
            BLSToExecutionChange,
            SignedBLSToExecutionChange,
            Attestation<C>,
            BeaconBlock<C>,
            BeaconBlockHeader,
            AttesterSlashing<C>,
            SignedBeaconBlock<C>,
            SignedBeaconBlockHeader,
            SignedVoluntaryExit,
            ProposerSlashing,
            ExecutionPayload<C>,
            ExecutionPayloadHeader<C>,
            Withdrawal,
            SigningData,
            SyncAggregate<C>,
            SyncCommittee<C>,
            BeaconState<C>,
            BeaconBlockBody<C>,
            StatusMessage,
            AggregateAndProof<C>,
            SignedAggregateAndProof<C>,
        }
    );
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

    let res = match_schema_and_decode!(
        (schema, config, &bytes, env) => {
            HistoricalSummary,
            AttestationData,
            IndexedAttestation<C>,
            Checkpoint,
            Eth1Data,
            Fork,
            ForkData,
            HistoricalBatch<C>,
            PendingAttestation<C>,
            Validator,
            DepositData,
            VoluntaryExit,
            Deposit,
            DepositMessage,
            BLSToExecutionChange,
            SignedBLSToExecutionChange,
            Attestation<C>,
            BeaconBlock<C>,
            BeaconBlockHeader,
            AttesterSlashing<C>,
            SignedBeaconBlock<C>,
            SignedBeaconBlockHeader,
            SignedVoluntaryExit,
            ProposerSlashing,
            ExecutionPayload<C>,
            ExecutionPayloadHeader<C>,
            Withdrawal,
            SigningData,
            SyncAggregate<C>,
            SyncCommittee<C>,
            BeaconState<C>,
            BeaconBlockBody<C>,
            StatusMessage,
            AggregateAndProof<C>,
            SignedAggregateAndProof<C>,
        }
    )?;
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

    let serialized = match_schema_and_hash!(
        (schema, config, map) => {
            Fork,
        }
    );
    Ok((atoms::ok(), bytes_to_binary(env, &serialized?)).encode(env))
}

rustler::init!("Elixir.Ssz", [to_ssz_rs, from_ssz_rs, hash_tree_root_rs]);
