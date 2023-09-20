use super::{config::Config, *};
use ssz_derive::{Decode, Encode};
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
