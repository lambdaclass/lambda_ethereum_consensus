//! # SSZ NIF
//!
//! To add a new type:
//!  - Add the type to the [`types`] module, using the [`gen_struct`] macro
//!  - Implement the necessary traits ([`FromElx`] and [`FromLH`]) for its attributes
//!  - Add the type to [`to_ssz`] and [`from_ssz`] "match" macros

pub(crate) mod lh_types;
pub(crate) mod types;
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
            AttestationData,
            Checkpoint,
            Eth1Data,
            Fork,
            ForkData,
            HistoricalBatchMainnet,
            HistoricalBatchMinimal,
            IndexedAttestationMainnet,
            PendingAttestationMainnet,
            Validator,
            DepositData,
            VoluntaryExit
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
            AttestationData,
            Checkpoint,
            Eth1Data,
            Fork,
            ForkData,
            HistoricalBatchMainnet,
            HistoricalBatchMinimal,
            IndexedAttestationMainnet,
            PendingAttestationMainnet,
            Validator,
            DepositData,
            VoluntaryExit
        }
    )
}

rustler::init!("Elixir.Ssz", [to_ssz, from_ssz]);

#[cfg(test)]
mod tests {
    use hex::FromHex;
    use lighthouse_types::{
        AggregateSignature, BitList, EthSpec, IndexedAttestation, MainnetEthSpec,
    };
    use ssz::Decode;

    use crate::lh_types::IndexedAttestationMainnet;

    #[test]
    fn test_deser() {
        let bytes = Vec::from_hex("E40000000F663F33D5BB3E93000000000000000008C7979023DADA9DB03775129CCF942CFA93C9B80323C9C6D08E3B6AA606D945FFFFFFFFFFFFFFFF32B67DD3EBC8C35409FACF0BE72E084DF7C9A2709AD6DAD1AA6C391906E8DB5EACD80A16640EAB5C00000000000000000000000000000000000000000000000000000000000000000ABCB9612CCC4C7FC56D04CCA3454ED88B062885D62CC3B6D4D4D9CE01AB0DFA25027125D07A160AEC95BBB6F88FA2E818C5A6FAAC5443A63000A7409932FBC46927DD547050A335822417F8F283DC23D91B0A6C2B4DAAB36F07B9542D52F79DEDA440DA8C87FBB8AC67073848423D3874A3DF150340AEBA").unwrap();
        IndexedAttestationMainnet::from_ssz_bytes(&bytes).unwrap();
        let x = <[u8; 96]>::from_hex("0abcb9612ccc4c7fc56d04cca3454ed88b062885d62cc3b6d4d4d9ce01ab0dfa25027125d07a160aec95bbb6f88fa2e818c5a6faac5443a63000a7409932fbc46927dd547050a335822417f8f283dc23d91b0a6c2b4daab36f07b9542d52f79d").unwrap();
        let sig = AggregateSignature::deserialize(&x).unwrap();
    }
}
