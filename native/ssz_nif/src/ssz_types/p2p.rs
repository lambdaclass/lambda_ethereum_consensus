use super::*;
use ssz_derive::{Decode, Encode};
use tree_hash_derive::TreeHash;

#[derive(Encode, Decode, TreeHash)]
pub(crate) struct StatusMessage {
    pub(crate) fork_digest: ForkDigest,
    pub(crate) finalized_root: Root,
    pub(crate) finalized_epoch: Epoch,
    pub(crate) head_root: Root,
    pub(crate) head_slot: Slot,
}

#[derive(Encode, Decode, TreeHash)]
pub(crate) struct BeaconBlocksByRangeRequest {
    pub(crate) start_slot: Slot,
    pub(crate) count: u64,
    pub(crate) step: u64,
}
