use rustler::NifStruct;

use crate::utils::{gen_struct, gen_struct_with_config};

use super::*;

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.AggregateAndProof"]
    pub(crate) struct AggregateAndProof<'a> {
        aggregator_index: ValidatorIndex,
        aggregate: Attestation<'a>,
        selection_proof: BLSSignature<'a>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.SignedAggregateAndProof"]
    pub(crate) struct SignedAggregateAndProof<'a> {
        message: AggregateAndProof<'a>,
        signature: BLSSignature<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.SyncCommitteeMessage"]
    pub(crate) struct SyncCommitteeMessage<'a> {
        slot: Slot,
        beacon_block_root: Root<'a>,
        validator_index: ValidatorIndex,
        signature: BLSSignature<'a>,
    }
);
