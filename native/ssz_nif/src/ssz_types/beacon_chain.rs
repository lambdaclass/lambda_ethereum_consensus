use super::config::Config;
use super::*;
use ssz_derive::{Decode, Encode};
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
pub(crate) struct IndexedAttestation<C: Config> {
    pub(crate) attesting_indices: VariableList<ValidatorIndex, C::MaxValidatorsPerCommittee>,
    pub(crate) data: AttestationData,
    pub(crate) signature: BLSSignature,
}

#[derive(Encode, Decode)]
pub(crate) struct PendingAttestation<C: Config> {
    pub(crate) aggregation_bits: BitList<C::MaxValidatorsPerCommittee>,
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
pub(crate) struct HistoricalBatch<C: Config> {
    pub(crate) block_roots: FixedVector<Root, C::SlotsPerHistoricalRoot>,
    pub(crate) state_roots: FixedVector<Root, C::SlotsPerHistoricalRoot>,
}

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
pub(crate) struct Attestation<C: Config> {
    pub(crate) aggregation_bits: BitList<C::MaxValidatorsPerCommittee>,
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
pub(crate) struct AttesterSlashing<C: Config> {
    pub(crate) attestation_1: IndexedAttestation<C>,
    pub(crate) attestation_2: IndexedAttestation<C>,
}

#[derive(Encode, Decode)]
pub(crate) struct SigningData {
    pub(crate) object_root: Root,
    pub(crate) domain: Domain,
}

#[derive(Encode, Decode)]
pub(crate) struct BLSToExecutionChange {
    pub(crate) validator_index: ValidatorIndex,
    pub(crate) from_bls_pubkey: BLSPubkey,
    pub(crate) to_execution_address: ExecutionAddress,
}

#[derive(Encode, Decode)]
pub(crate) struct SignedBLSToExecutionChange {
    pub(crate) message: BLSToExecutionChange,
    pub(crate) signature: BLSSignature,
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
pub(crate) struct SyncAggregate<C: Config> {
    pub(crate) sync_committee_bits: BitVector<C::SyncCommitteeSize>,
    pub(crate) sync_committee_signature: BLSSignature,
}

#[derive(Encode, Decode)]
pub(crate) struct Withdrawal {
    pub(crate) index: WithdrawalIndex,
    pub(crate) validator_index: ValidatorIndex,
    pub(crate) address: ExecutionAddress,
    pub(crate) amount: Gwei,
}

#[derive(Encode, Decode)]
pub(crate) struct ExecutionPayloadHeader<C: Config> {
    pub(crate) parent_hash: Hash32,
    pub(crate) fee_recipient: ExecutionAddress,
    pub(crate) state_root: Root,
    pub(crate) receipts_root: Root,
    pub(crate) logs_bloom: FixedVector<u8, C::BytesPerLogsBloom>,
    pub(crate) prev_randao: Bytes32,
    pub(crate) block_number: u64,
    pub(crate) gas_limit: u64,
    pub(crate) gas_used: u64,
    pub(crate) timestamp: u64,
    pub(crate) extra_data: VariableList<u8, C::MaxExtraDataBytes>,
    pub(crate) base_fee_per_gas: Uint256,
    pub(crate) block_hash: Hash32,
    pub(crate) transactions_root: Root,
    pub(crate) withdrawals_root: Root,
}

#[derive(Encode, Decode)]
pub(crate) struct ExecutionPayload<C: Config> {
    pub(crate) parent_hash: Hash32,
    pub(crate) fee_recipient: ExecutionAddress,
    pub(crate) state_root: Root,
    pub(crate) receipts_root: Root,
    pub(crate) logs_bloom: FixedVector<u8, C::BytesPerLogsBloom>,
    pub(crate) prev_randao: Bytes32,
    pub(crate) block_number: u64,
    pub(crate) gas_limit: u64,
    pub(crate) gas_used: u64,
    pub(crate) timestamp: u64,
    pub(crate) extra_data: VariableList<u8, C::MaxExtraDataBytes>,
    pub(crate) base_fee_per_gas: Uint256,
    pub(crate) block_hash: Hash32,
    pub(crate) transactions: VariableList<Transaction, C::MaxTransactionsPerPayload>,
    pub(crate) withdrawals: VariableList<Withdrawal, C::MaxWithdrawalsPerPayload>,
}

#[derive(Encode, Decode)]
pub(crate) struct SyncCommittee<C: Config> {
    pub(crate) pubkeys: FixedVector<BLSPubkey, C::SyncCommitteeSize>,
    pub(crate) aggregate_pubkey: BLSPubkey,
}
