use rustler::NifStruct;

use crate::utils::gen_struct;

use super::*;

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.StatusMessage"]
    pub(crate) struct StatusMessage<'a> {
        fork_digest: ForkDigest<'a>,
        finalized_root: Root<'a>,
        finalized_epoch: Epoch,
        head_root: Root<'a>,
        head_slot: Slot,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.BeaconBlocksByRangeRequest"]
    pub(crate) struct BeaconBlocksByRangeRequest {
        start_slot: Slot,
        count: u64,
        step: u64,
    }
);
