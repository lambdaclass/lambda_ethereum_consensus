use super::{config::Config, *};
use ssz_derive::{Decode, Encode};
use ssz_types::BitVector;
use tree_hash_derive::TreeHash;

#[derive(Encode, Decode, TreeHash)]
pub(crate) struct AggregateAndProof<C: Config> {
    pub(crate) aggregator_index: ValidatorIndex,
    pub(crate) aggregate: Attestation<C>,
    pub(crate) selection_proof: BLSSignature,
}

#[derive(Encode, Decode, TreeHash)]
pub(crate) struct SignedAggregateAndProof<C: Config> {
    pub(crate) message: AggregateAndProof<C>,
    pub(crate) signature: BLSSignature,
}

#[derive(Encode, Decode, TreeHash)]
pub(crate) struct SyncCommitteeMessage {
    pub(crate) slot: Slot,
    pub(crate) beacon_block_root: Root,
    pub(crate) validator_index: ValidatorIndex,
    pub(crate) signature: BLSSignature,
}

#[derive(Encode, Decode, TreeHash)]
pub(crate) struct SyncCommitteeContribution<C: Config> {
    pub(crate) slot: Slot,
    pub(crate) beacon_block_root: Root,
    pub(crate) subcommittee_index: u64,
    pub(crate) aggregation_bits: BitVector<C::SyncSubcommitteeSize>,
    pub(crate) signature: BLSSignature,
}

#[derive(Encode, Decode, TreeHash)]
pub(crate) struct ContributionAndProof<C: Config> {
    pub(crate) aggregator_index: ValidatorIndex,
    pub(crate) contribution: SyncCommitteeContribution<C>,
    pub(crate) selection_proof: BLSSignature,
}

#[derive(Encode, Decode, TreeHash)]
pub(crate) struct SignedContributionAndProof<C: Config> {
    pub(crate) message: ContributionAndProof<C>,
    pub(crate) signature: BLSSignature,
}
