use ssz_derive::{Decode, Encode};

type Byte32 = [u8; 32];
type Root = Byte32;

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
