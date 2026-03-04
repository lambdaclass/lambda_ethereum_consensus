use rustler::NifStruct;

use crate::utils::{gen_struct, gen_struct_with_config};

use super::*;

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.StatusMessage"]
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
    #[module = "Types.BeaconBlocksByRangeRequest"]
    pub(crate) struct BeaconBlocksByRangeRequest {
        start_slot: Slot,
        count: u64,
        step: u64,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.Metadata"]
    pub(crate) struct Metadata<'a> {
        seq_number: u64,
        attnets: Binary<'a>,
        syncnets: Binary<'a>,
        custody_group_count: u64,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.BlobSidecar"]
    pub(crate) struct BlobSidecar<'a> {
        index: BlobIndex,
        blob: Blob<'a>,
        kzg_commitment: KZGCommitment<'a>,
        kzg_proof: KZGProof<'a>,
        signed_block_header: SignedBeaconBlockHeader<'a>,
        kzg_commitment_inclusion_proof: Vec<Bytes32<'a>>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.BlobIdentifier"]
    pub(crate) struct BlobIdentifier<'a> {
        block_root: Root<'a>,
        index: BlobIndex,
    }
);

// Fulu / PeerDAS (EIP-7594)
gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.DataColumnSidecar"]
    pub(crate) struct DataColumnSidecar<'a> {
        index: ColumnIndex,
        column: Vec<Cell<'a>>,
        kzg_commitments: Vec<KZGCommitment<'a>>,
        kzg_proofs: Vec<KZGProof<'a>>,
        signed_block_header: SignedBeaconBlockHeader<'a>,
        kzg_commitments_inclusion_proof: Vec<Bytes32<'a>>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.DataColumnIdentifier"]
    pub(crate) struct DataColumnIdentifier<'a> {
        block_root: Root<'a>,
        index: ColumnIndex,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.DataColumnsByRootIdentifier"]
    pub(crate) struct DataColumnsByRootIdentifier<'a> {
        block_root: Root<'a>,
        columns: Vec<ColumnIndex>,
    }
);
