//! # SSZ NIF
//!
//! To add a new type:
//!  - Add the type to the [`elx_types`] and [`ssz_types`] modules, using the [`gen_struct`](utils::gen_struct) macro
//!  - Implement the necessary traits ([`FromElx`](utils::from_elx::FromElx) and [`FromSsz`](utils::from_ssz::FromSsz)) for its attributes
//!  - Add the type to [`to_ssz_rs`] and [`from_ssz_rs`] "match" macros

pub(crate) mod elx_types;
pub(crate) mod ssz_types;
pub(crate) mod utils;

use crate::utils::{helpers::bytes_to_binary, match_schema_and_decode, match_schema_and_encode};
use rustler::{Atom, Binary, Encoder, Env, NifResult, Term};

mod atoms {
    use rustler::atoms;

    atoms! {
        ok,
    }
}

const PREFIX_SIZE: usize = "Elixir.SszTypes.".len();

#[rustler::nif]
fn to_ssz_rs<'env>(env: Env<'env>, map: Term, schema: Atom) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string()?;
    let Some(schema) = schema.get(PREFIX_SIZE..) else {
        return Err(rustler::Error::BadArg);
    };
    let config = "MainnetConfig";
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
            BeaconBlockHeader,
            AttesterSlashing<C>,
            SignedBeaconBlockHeader,
            SignedVoluntaryExit,
            ProposerSlashing,
            ExecutionPayload<C>,
            ExecutionPayloadHeader<C>,
            Withdrawal,
            SigningData,
            SyncAggregate<C>,
            SyncCommittee<C>,
        }
    );
    Ok((atoms::ok(), bytes_to_binary(env, &serialized?)).encode(env))
}

#[rustler::nif]
fn from_ssz_rs<'env>(env: Env<'env>, bytes: Binary, schema: Atom) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string()?;
    let Some(schema) = schema.get(PREFIX_SIZE..) else {
        return Err(rustler::Error::BadArg);
    };
    let config = "MainnetConfig";
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
            BeaconBlockHeader,
            AttesterSlashing<C>,
            SignedBeaconBlockHeader,
            SignedVoluntaryExit,
            ProposerSlashing,
            ExecutionPayload<C>,
            ExecutionPayloadHeader<C>,
            Withdrawal,
            SigningData,
            SyncAggregate<C>,
            SyncCommittee<C>,
        }
    )?;
    Ok((atoms::ok(), res).encode(env))
}

rustler::init!("Elixir.Ssz", [to_ssz_rs, from_ssz_rs]);
