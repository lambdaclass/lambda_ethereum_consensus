use super::*;
use ethereum_types::U256;
use ssz_derive::{Decode, Encode};
use ssz_types::typenum::Unsigned;
use ssz_types::{BitList, BitVector};

#[derive(Encode, Decode)]
pub(crate) struct Fork {
    pub(crate) previous_version: Version,
    pub(crate) current_version: Version,
    pub(crate) epoch: Epoch,
}

#[derive(Encode, Decode)]
pub(crate) struct ForkData {
    pub(crate) current_version: Version,
    pub(crate) genesis_validators_root: Root,
}

#[derive(Encode, Decode)]
pub(crate) struct Checkpoint {
    pub(crate) epoch: Epoch,
    pub(crate) root: Root,
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
pub(crate) struct AttestationData {
    pub(crate) slot: Slot,
    pub(crate) index: CommitteeIndex,
    pub(crate) beacon_block_root: Root,
    pub(crate) source: Checkpoint,
    pub(crate) target: Checkpoint,
}

#[derive(Encode, Decode)]
pub(crate) struct IndexedAttestation {
    pub(crate) attesting_indices:
        VariableList<ValidatorIndex, /* MAX_VALIDATORS_PER_COMMITTEE */ typenum::U2048>,
    pub(crate) data: AttestationData,
    pub(crate) signature: BLSSignature,
}

#[derive(Encode, Decode)]
pub(crate) struct PendingAttestation {
    pub(crate) aggregation_bits: BitList</* MAX_VALIDATORS_PER_COMMITTEE */ typenum::U2048>,
    pub(crate) data: AttestationData,
    pub(crate) inclusion_delay: Slot,
    pub(crate) proposer_index: ValidatorIndex,
}

#[derive(Encode, Decode)]
pub(crate) struct Eth1Data {
    pub(crate) deposit_root: Root,
    pub(crate) deposit_count: u64,
    pub(crate) block_hash: Hash32,
}

#[derive(Encode, Decode)]
pub(crate) struct HistoricalBatchBase<N: Unsigned> {
    pub(crate) block_roots: FixedVector<Root, /* SLOTS_PER_HISTORICAL_ROOT */ N>,
    pub(crate) state_roots: FixedVector<Root, /* SLOTS_PER_HISTORICAL_ROOT */ N>,
}

pub(crate) type HistoricalBatch = HistoricalBatchBase<typenum::U8192>;
pub(crate) type HistoricalBatchMinimal = HistoricalBatchBase<typenum::U64>;

#[derive(Encode, Decode)]
pub(crate) struct DepositMessage {
    pub(crate) pubkey: BLSPubkey,
    pub(crate) withdrawal_credentials: Bytes32,
    pub(crate) amount: Gwei,
}

#[derive(Encode, Decode)]
pub(crate) struct DepositData {
    pub(crate) pubkey: BLSPubkey,
    pub(crate) withdrawal_credentials: Bytes32,
    pub(crate) amount: Gwei,
    pub(crate) signature: BLSSignature,
}

#[derive(Encode, Decode)]
pub(crate) struct HistoricalSummary {
    pub(crate) block_summary_root: Root,
    pub(crate) state_summary_root: Root,
}

#[derive(Encode, Decode)]
pub(crate) struct Deposit {
    pub(crate) proof: FixedVector<Bytes32, /* DEPOSIT_CONTRACT_TREE_DEPTH + 1 */ typenum::U33>,
    pub(crate) data: DepositData,
}

#[derive(Encode, Decode)]
pub(crate) struct VoluntaryExit {
    pub(crate) epoch: Epoch,
    pub(crate) validator_index: ValidatorIndex,
}

#[derive(Encode, Decode)]
pub(crate) struct Attestation {
    pub(crate) aggregation_bits: BitList</* MAX_VALIDATORS_PER_COMMITTEE */ typenum::U2048>,
    pub(crate) data: AttestationData,
    pub(crate) signature: BLSSignature,
}

#[derive(Encode, Decode)]
pub(crate) struct BeaconBlockHeader {
    pub(crate) slot: Slot,
    pub(crate) proposer_index: ValidatorIndex,
    pub(crate) parent_root: Root,
    pub(crate) state_root: Root,
    pub(crate) body_root: Root,
}

#[derive(Encode, Decode)]
pub(crate) struct SignedBeaconBlockHeader {
    pub(crate) message: BeaconBlockHeader,
    pub(crate) signature: BLSSignature,
}

#[derive(Encode, Decode)]
pub(crate) struct AttesterSlashing {
    pub(crate) attestation_1: IndexedAttestation,
    pub(crate) attestation_2: IndexedAttestation,
}

#[derive(Encode, Decode)]
pub(crate) struct SigningData {
    pub(crate) object_root: Root,
    pub(crate) domain: Domain,
}

#[derive(Encode, Decode)]
pub(crate) struct SignedVoluntaryExit {
    pub(crate) message: VoluntaryExit,
    pub(crate) signature: BLSSignature,
}

#[derive(Encode, Decode)]
pub(crate) struct ProposerSlashing {
    pub(crate) signed_header_1: SignedBeaconBlockHeader,
    pub(crate) signed_header_2: SignedBeaconBlockHeader,
}

#[derive(Encode, Decode)]
pub(crate) struct SyncAggregateBase<N: Unsigned> {
    pub(crate) sync_committee_bits: BitVector</* SYNC_COMMITTEE_SIZE */ N>,
    pub(crate) sync_committee_signature: BLSSignature,
}

pub(crate) type SyncAggregate = SyncAggregateBase<typenum::U512>;
pub(crate) type SyncAggregateMinimal = SyncAggregateBase<typenum::U32>;

#[derive(Encode, Decode)]
pub(crate) struct Withdrawal {
    pub(crate) index: WithdrawalIndex,
    pub(crate) validator_index: ValidatorIndex,
    pub(crate) address: ExecutionAddress,
    pub(crate) amount: Gwei,
}

#[derive(Encode, Decode)]
pub(crate) struct ExecutionPayloadHeader {
    pub(crate) parent_hash: Hash32,
    pub(crate) fee_recipient: ExecutionAddress,
    pub(crate) state_root: Root,
    pub(crate) receipts_root: Root,
    pub(crate) logs_bloom: FixedVector<u8, /* BYTES_PER_LOGS_BLOOM */ typenum::U256>,
    pub(crate) prev_randao: Bytes32,
    pub(crate) block_number: u64,
    pub(crate) gas_limit: u64,
    pub(crate) gas_used: u64,
    pub(crate) timestamp: u64,
    pub(crate) extra_data: VariableList<u8, /* MAX_EXTRA_DATA_BYTES */ typenum::U32>,
    pub(crate) base_fee_per_gas: U256,
    pub(crate) block_hash: Hash32,
    pub(crate) transactions_root: Root,
    pub(crate) withdrawals_root: Root,
}

#[derive(Encode, Decode)]
pub(crate) struct ExecutionPayload {
    pub(crate) parent_hash: Hash32,
    pub(crate) fee_recipient: ExecutionAddress,
    pub(crate) state_root: Root,
    pub(crate) receipts_root: Root,
    pub(crate) logs_bloom: FixedVector<u8, /* BYTES_PER_LOGS_BLOOM */ typenum::U256>,
    pub(crate) prev_randao: Bytes32,
    pub(crate) block_number: u64,
    pub(crate) gas_limit: u64,
    pub(crate) gas_used: u64,
    pub(crate) timestamp: u64,
    pub(crate) extra_data: VariableList<u8, /* MAX_EXTRA_DATA_BYTES */ typenum::U32>,
    pub(crate) base_fee_per_gas: U256,
    pub(crate) block_hash: Hash32,
    pub(crate) transactions:
        VariableList<Transaction, /* MAX_TRANSACTIONS_PER_PAYLOAD */ typenum::U1048576>,
    pub(crate) withdrawals:
        VariableList<Withdrawal, /* MAX_WITHDRAWALS_PER_PAYLOAD */ typenum::U16>,
}
