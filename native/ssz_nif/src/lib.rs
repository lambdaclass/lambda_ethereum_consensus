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
    let schema = schema.to_term(env).atom_to_string().unwrap();
    let schema = &schema[PREFIX_SIZE..];
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
            BLSToExecutionChange,
            Attestation,
            BeaconBlockHeader,
            AttesterSlashing,
            SignedBeaconBlockHeader,
            SignedVoluntaryExit,
            ProposerSlashing,
            SigningData,
        }
    );
    Ok((atoms::ok(), bytes_to_binary(env, &serialized?)).encode(env))
}

#[rustler::nif]
fn from_ssz<'env>(env: Env<'env>, bytes: Binary, schema: Atom) -> Result<Term<'env>, String> {
    let schema = schema.to_term(env).atom_to_string().unwrap();
    let schema = &schema[PREFIX_SIZE..];
    match_schema_and_decode!(
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
            BLSToExecutionChange,
            Attestation,
            BeaconBlockHeader,
            AttesterSlashing,
            SignedBeaconBlockHeader,
            SignedVoluntaryExit,
            ProposerSlashing,
            SigningData,
        }
    )
}

rustler::init!("Elixir.Ssz", [to_ssz, from_ssz]);
