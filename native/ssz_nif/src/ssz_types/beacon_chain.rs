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

#[derive(Encode, Decode)]
pub(crate) struct Validator {
    pub(crate) pubkey: BLSPubkey,
    pub(crate) withdrawal_credentials: Bytes32,
    pub(crate) effective_balance: Gwei,
    pub(crate) slashed: bool,
    pub(crate) activation_eligibility_epoch: Epoch,
    pub(crate) activation_epoch: Epoch,
    pub(crate) exit_epoch: Epoch,
    pub(crate) withdrawable_epoch: Epoch,
}

#[derive(Encode, Decode)]
pub(crate) struct VoluntaryExit {
    pub(crate) epoch: Epoch,
    pub(crate) validator_index: ValidatorIndex,
}

#[derive(Encode, Decode, Default)]
pub(crate) struct AttestationData {
    pub(crate) slot: u64,
    pub(crate) index: u64,
    pub(crate) beacon_block_root: Root,
    pub(crate) source: Checkpoint,
    pub(crate) target: Checkpoint,
}

#[derive(Encode, Decode, Default)]
pub(crate) struct Fork {
    pub(crate) previous_version: Version,
    pub(crate) current_version: Version,
    pub(crate) epoch: u64,
}

#[derive(Encode, Decode, Default)]
pub(crate) struct ForkData {
    pub(crate) current_version: Version,
    pub(crate) genesis_validators_root: Root,
}

#[derive(Encode, Decode, Default)]
pub(crate) struct Eth1Data {
    pub(crate) deposit_root: Root,
    pub(crate) deposit_count: u64,
    pub(crate) block_hash: Hash32,
}

#[derive(Encode, Decode, Default)]
pub(crate) struct HistoricalBatch {
    pub(crate) block_roots: Vec<Root>,
    pub(crate) state_roots: Vec<Root>,
}

#[derive(Encode, Decode)]
pub(crate) struct Deposit {
    pub(crate) proof: FixedVector<Bytes32, /* DEPOSIT_CONTRACT_TREE_DEPTH + 1 */ typenum::U33>,
    pub(crate) data: DepositData,
}

#[derive(Encode, Decode)]
pub(crate) struct DepositData {
    pub(crate) pubkey: BLSPubkey,
    pub(crate) withdrawal_credentials: Bytes32,
    pub(crate) amount: Gwei,
    pub(crate) signature: BLSSignature,
}
