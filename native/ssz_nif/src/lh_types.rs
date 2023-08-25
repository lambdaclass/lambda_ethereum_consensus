//! This module re-exports all the types from [`lighthouse_types`].
//! It also adds some aliases for types that receive generic arguments.

pub(crate) use lighthouse_types::*;

pub(crate) type IndexedAttestationMainnet = IndexedAttestation<MainnetEthSpec>;
pub(crate) type PendingAttestationMainnet = PendingAttestation<MainnetEthSpec>;
pub(crate) type HistoricalBatchMainnet = HistoricalBatch<MainnetEthSpec>;
pub(crate) type HistoricalBatchMinimal = HistoricalBatch<MinimalEthSpec>;
