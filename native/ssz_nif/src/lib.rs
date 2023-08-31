//! # SSZ NIF
//!
//! To add a new type:
//!  - Add the type to the [`types`] module, using the [`gen_struct`] macro
//!  - Implement the necessary traits ([`FromElx`] and [`FromSsz`]) for its attributes
//!  - Add the type to [`to_ssz`] and [`from_ssz`] "match" macros

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
fn to_ssz<'env>(env: Env<'env>, map: Term, schema: Atom) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string()?;
    let Some(schema) = schema.get(PREFIX_SIZE..) else {
        return Err(rustler::Error::BadArg);
    };
    let serialized = match_schema_and_encode!(
        (schema, map) => {
            HistoricalSummary,
            AttestationData,
            IndexedAttestation,
            Checkpoint,
            Eth1Data,
            Fork,
            ForkData,
            HistoricalBatch,
            HistoricalBatchMinimal,
            PendingAttestation,
            Validator,
            DepositData,
            VoluntaryExit,
            Deposit,
            DepositMessage,
            Attestation,
            BeaconBlockHeader,
            AttesterSlashing,
            SignedBeaconBlockHeader,
            SignedVoluntaryExit,
            ProposerSlashing,
            ExecutionPayload,
            ExecutionPayloadHeader,
            Withdrawal,
            SigningData,
            SyncAggregate,
            SyncAggregateMinimal,
        }
    );
    Ok((atoms::ok(), bytes_to_binary(env, &serialized?)).encode(env))
}

#[rustler::nif]
fn from_ssz_raw<'env>(env: Env<'env>, bytes: Binary, schema: Atom) -> NifResult<Term<'env>> {
    let schema = schema.to_term(env).atom_to_string()?;
    let Some(schema) = schema.get(PREFIX_SIZE..) else {
        return Err(rustler::Error::BadArg);
    };
    let res = match_schema_and_decode!(
        (schema, &bytes, env) => {
            HistoricalSummary,
            AttestationData,
            IndexedAttestation,
            Checkpoint,
            Eth1Data,
            Fork,
            ForkData,
            HistoricalBatch,
            HistoricalBatchMinimal,
            PendingAttestation,
            Validator,
            DepositData,
            VoluntaryExit,
            Deposit,
            DepositMessage,
            Attestation,
            BeaconBlockHeader,
            AttesterSlashing,
            SignedBeaconBlockHeader,
            SignedVoluntaryExit,
            ProposerSlashing,
            ExecutionPayload,
            ExecutionPayloadHeader,
            Withdrawal,
            SigningData,
            SyncAggregate,
            SyncAggregateMinimal,
        }
    )?;
    Ok((atoms::ok(), res).encode(env))
}

rustler::init!("Elixir.Ssz", [to_ssz, from_ssz_raw]);
