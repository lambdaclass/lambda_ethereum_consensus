use super::{config::Config, *};
use ssz_derive::{Decode, Encode};
use ssz_types::BitVector;
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

#[derive(Encode, Decode, TreeHash)]
pub(crate) struct Metadata<C: Config> {
    pub(crate) seq_number: u64,
    pub(crate) attnets: BitVector<C::AttestationSubnetCount>,
    pub(crate) syncnets: BitVector<C::SyncCommitteeSubnetCount>,
}

#[derive(Encode, Decode, TreeHash)]
pub(crate) struct BlobSidecar<C: Config> {
    pub(crate) index: BlobIndex,
    pub(crate) blob: Blob<C>,
    pub(crate) kzg_commitment: KZGCommitment,
    pub(crate) kzg_proof: KZGProof,
    pub(crate) signed_block_header: SignedBeaconBlockHeader,
    pub(crate) kzg_commitment_inclusion_proof:
        FixedVector<Bytes32, C::KzgCommitmentInclusionProofDepth>,
}

#[derive(Encode, Decode, TreeHash)]
pub(crate) struct BlobIdentifier {
    pub(crate) block_root: Root,
    pub(crate) index: BlobIndex,
}
