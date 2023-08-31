use super::*;
use crate::utils::gen_struct;
use rustler::{Binary, NifStruct};

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.Fork"]
    pub(crate) struct Fork<'a> {
        previous_version: Version<'a>,
        current_version: Version<'a>,
        epoch: Epoch,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.ForkData"]
    pub(crate) struct ForkData<'a> {
        current_version: Version<'a>,
        genesis_validators_root: Root<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.Checkpoint"]
    pub(crate) struct Checkpoint<'a> {
        epoch: Epoch,
        root: Root<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.Validator"]
    pub(crate) struct Validator<'a> {
        pubkey: BLSPubkey<'a>,
        withdrawal_credentials: Bytes32<'a>,
        effective_balance: Gwei,
        slashed: bool,
        activation_eligibility_epoch: Epoch,
        activation_epoch: Epoch,
        exit_epoch: Epoch,
        withdrawable_epoch: Epoch,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.AttestationData"]
    pub(crate) struct AttestationData<'a> {
        slot: Slot,
        index: CommitteeIndex,
        beacon_block_root: Root<'a>,
        source: Checkpoint<'a>,
        target: Checkpoint<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.IndexedAttestation"]
    pub(crate) struct IndexedAttestation<'a> {
        attesting_indices: Vec<ValidatorIndex>, // Max size: MAX_VALIDATORS_PER_COMMITTEE
        data: AttestationData<'a>,
        signature: BLSSignature<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.PendingAttestation"]
    pub(crate) struct PendingAttestation<'a> {
        aggregation_bits: Binary<'a>, // Max size: MAX_VALIDATORS_PER_COMMITTEE
        data: AttestationData<'a>,
        inclusion_delay: Slot,
        proposer_index: ValidatorIndex,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.Eth1Data"]
    pub(crate) struct Eth1Data<'a> {
        deposit_root: Root<'a>,
        deposit_count: u64,
        block_hash: Hash32<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.HistoricalBatch"]
    pub(crate) struct HistoricalBatch<'a> {
        block_roots: Vec<Root<'a>>,
        state_roots: Vec<Root<'a>>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.HistoricalBatchMinimal"]
    pub(crate) struct HistoricalBatchMinimal<'a> {
        block_roots: Vec<Root<'a>>,
        state_roots: Vec<Root<'a>>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.DepositMessage"]
    pub(crate) struct DepositMessage<'a> {
        pubkey: BLSPubkey<'a>,
        withdrawal_credentials: Bytes32<'a>,
        amount: Gwei,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.DepositData"]
    pub(crate) struct DepositData<'a> {
        pubkey: BLSPubkey<'a>,
        withdrawal_credentials: Bytes32<'a>,
        amount: Gwei,
        signature: BLSSignature<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.HistoricalSummary"]
    pub(crate) struct HistoricalSummary<'a> {
        pub(crate) block_summary_root: Root<'a>,
        pub(crate) state_summary_root: Root<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.Deposit"]
    pub(crate) struct Deposit<'a> {
        proof: Vec<Bytes32<'a>>,
        data: DepositData<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.VoluntaryExit"]
    pub(crate) struct VoluntaryExit {
        epoch: Epoch,
        validator_index: ValidatorIndex,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.Attestation"]
    pub(crate) struct Attestation<'a> {
        aggregation_bits: Binary<'a>,
        data: AttestationData<'a>,
        signature: BLSSignature<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.BeaconBlockHeader"]
    pub(crate) struct BeaconBlockHeader<'a> {
        slot: Slot,
        proposer_index: ValidatorIndex,
        parent_root: Root<'a>,
        state_root: Root<'a>,
        body_root: Root<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.AttesterSlashing"]
    pub(crate) struct AttesterSlashing<'a> {
        attestation_1: IndexedAttestation<'a>,
        attestation_2: IndexedAttestation<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.SignedVoluntaryExit"]
    pub(crate) struct SignedVoluntaryExit<'a> {
        message: VoluntaryExit,
        signature: BLSSignature<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.SignedBeaconBlockHeader"]
    pub(crate) struct SignedBeaconBlockHeader<'a> {
        message: BeaconBlockHeader<'a>,
        signature: BLSSignature<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.ProposerSlashing"]
    pub(crate) struct ProposerSlashing<'a> {
        signed_header_1: SignedBeaconBlockHeader<'a>,
        signed_header_2: SignedBeaconBlockHeader<'a>,
    }
);
gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.Withdrawal"]
    pub(crate) struct Withdrawal<'a> {
        index: WithdrawalIndex,
        validator_index: ValidatorIndex,
        address: ExecutionAddress<'a>,
        amount: Gwei,
    }
);
gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.ExecutionPayloadHeader"]
    pub(crate) struct ExecutionPayloadHeader<'a> {
        parent_hash: Hash32<'a>,
        fee_recipient: ExecutionAddress<'a>,
        state_root: Root<'a>,
        receipts_root: Root<'a>,
        logs_bloom: Binary<'a>,
        prev_randao: Bytes32<'a>,
        block_number: u64,
        gas_limit: u64,
        gas_used: u64,
        timestamp: u64,
        extra_data: Binary<'a>,
        base_fee_per_gas: String,
        block_hash: Hash32<'a>,
        transactions_root: Root<'a>,
        withdrawals_root: Root<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.ExecutionPayload"]
    pub(crate) struct ExecutionPayload<'a> {
        parent_hash: Hash32<'a>,
        fee_recipient: ExecutionAddress<'a>,
        state_root: Root<'a>,
        receipts_root: Root<'a>,
        logs_bloom: Binary<'a>,
        prev_randao: Bytes32<'a>,
        block_number: u64,
        gas_limit: u64,
        gas_used: u64,
        timestamp: u64,
        extra_data: Binary<'a>,
        base_fee_per_gas: String,
        block_hash: Hash32<'a>,
        transactions: Vec<Transaction<'a>>,
        withdrawals: Vec<Withdrawal<'a>>,
    }
);
