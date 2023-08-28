use super::*;
use ssz_derive::{Decode, Encode};

#[derive(Encode, Decode, Default)]
pub(crate) struct Checkpoint {
    pub(crate) epoch: u64,
    pub(crate) root: Root,
}

#[derive(Encode, Decode, Default)]
pub(crate) struct HistoricalSummary {
    pub(crate) block_summary_root: Root,
    pub(crate) state_summary_root: Root,
}
