//! This module re-exports all the types from [`lighthouse_types`].
//! It also adds some aliases for types that receive generic arguments.

pub(crate) use lighthouse_types::*;
use ssz_derive::{Decode, Encode};

pub(crate) type PendingAttestationMainnet = PendingAttestation<MainnetEthSpec>;
pub(crate) type HistoricalBatchMainnet = HistoricalBatch<MainnetEthSpec>;
pub(crate) type HistoricalBatchMinimal = HistoricalBatch<MinimalEthSpec>;

type Byte32 = [u8; 32];
type Root = Byte32;

#[derive(Encode, Decode, Default)]
pub(crate) struct HistoricalSummary {
    pub(crate) block_summary_root: Root,
    pub(crate) state_summary_root: Root,
}
