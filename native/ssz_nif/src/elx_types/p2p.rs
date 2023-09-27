use rustler::NifStruct;

use crate::utils::{gen_struct, gen_struct_with_config};

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

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "SszTypes.BeaconBlocksByRangeRequest"]
    pub(crate) struct BeaconBlocksByRangeResponse<'a> {
        body: Vec<SignedBeaconBlock<'a>>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.BeaconBlocksByRootRequest"]
    pub(crate) struct BeaconBlocksByRootRequest<'a> {
        block_roots: Vec<Root<'a>>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "SszTypes.BeaconBlocksByRootResponse"]
    pub(crate) struct BeaconBlocksByRootResponse<'a> {
        blocks: Vec<SignedBeaconBlock<'a>>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "SszTypes.Metadata"]
    pub(crate) struct Metadata<'a> {
        seq_number: u64,
        attnets: Binary<'a>,
        syncnets: Binary<'a>,
    }
);
