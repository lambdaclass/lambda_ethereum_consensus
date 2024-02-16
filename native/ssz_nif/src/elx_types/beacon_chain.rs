use super::*;
use crate::utils::{gen_struct, gen_struct_with_config};
use rustler::{Binary, NifStruct};

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.Fork"]
    pub(crate) struct Fork<'a> {
        previous_version: Version<'a>,
        current_version: Version<'a>,
        epoch: Epoch,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.ForkData"]
    pub(crate) struct ForkData<'a> {
        current_version: Version<'a>,
        genesis_validators_root: Root<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.Checkpoint"]
    pub(crate) struct Checkpoint<'a> {
        epoch: Epoch,
        root: Root<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.Validator"]
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
    #[module = "Types.AttestationData"]
    pub(crate) struct AttestationData<'a> {
        slot: Slot,
        index: CommitteeIndex,
        beacon_block_root: Root<'a>,
        source: Checkpoint<'a>,
        target: Checkpoint<'a>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.IndexedAttestation"]
    pub(crate) struct IndexedAttestation<'a> {
        attesting_indices: Vec<ValidatorIndex>, // Max size: MAX_VALIDATORS_PER_COMMITTEE
        data: AttestationData<'a>,
        signature: BLSSignature<'a>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.PendingAttestation"]
    pub(crate) struct PendingAttestation<'a> {
        aggregation_bits: Binary<'a>, // Max size: MAX_VALIDATORS_PER_COMMITTEE
        data: AttestationData<'a>,
        inclusion_delay: Slot,
        proposer_index: ValidatorIndex,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.Eth1Data"]
    pub(crate) struct Eth1Data<'a> {
        deposit_root: Root<'a>,
        deposit_count: u64,
        block_hash: Hash32<'a>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.HistoricalBatch"]
    pub(crate) struct HistoricalBatch<'a> {
        block_roots: Vec<Root<'a>>,
        state_roots: Vec<Root<'a>>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.DepositMessage"]
    pub(crate) struct DepositMessage<'a> {
        pubkey: BLSPubkey<'a>,
        withdrawal_credentials: Bytes32<'a>,
        amount: Gwei,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.DepositData"]
    pub(crate) struct DepositData<'a> {
        pubkey: BLSPubkey<'a>,
        withdrawal_credentials: Bytes32<'a>,
        amount: Gwei,
        signature: BLSSignature<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.HistoricalSummary"]
    pub(crate) struct HistoricalSummary<'a> {
        pub(crate) block_summary_root: Root<'a>,
        pub(crate) state_summary_root: Root<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.Deposit"]
    pub(crate) struct Deposit<'a> {
        proof: Vec<Bytes32<'a>>,
        data: DepositData<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.VoluntaryExit"]
    pub(crate) struct VoluntaryExit {
        epoch: Epoch,
        validator_index: ValidatorIndex,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.Attestation"]
    pub(crate) struct Attestation<'a> {
        aggregation_bits: Binary<'a>,
        data: AttestationData<'a>,
        signature: BLSSignature<'a>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.BeaconBlock"]
    pub(crate) struct BeaconBlock<'a> {
        slot: Slot,
        proposer_index: ValidatorIndex,
        parent_root: Root<'a>,
        state_root: Root<'a>,
        body: BeaconBlockBody<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.BeaconBlockHeader"]
    pub(crate) struct BeaconBlockHeader<'a> {
        slot: Slot,
        proposer_index: ValidatorIndex,
        parent_root: Root<'a>,
        state_root: Root<'a>,
        body_root: Root<'a>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.AttesterSlashing"]
    pub(crate) struct AttesterSlashing<'a> {
        attestation_1: IndexedAttestation<'a>,
        attestation_2: IndexedAttestation<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.SignedVoluntaryExit"]
    pub(crate) struct SignedVoluntaryExit<'a> {
        message: VoluntaryExit,
        signature: BLSSignature<'a>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.SignedBeaconBlock"]
    pub(crate) struct SignedBeaconBlock<'a> {
        message: BeaconBlock<'a>,
        signature: BLSSignature<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.SignedBeaconBlockHeader"]
    pub(crate) struct SignedBeaconBlockHeader<'a> {
        message: BeaconBlockHeader<'a>,
        signature: BLSSignature<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.BLSToExecutionChange"]
    pub(crate) struct BLSToExecutionChange<'a> {
        validator_index: ValidatorIndex,
        from_bls_pubkey: BLSPubkey<'a>,
        to_execution_address: ExecutionAddress<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.SignedBLSToExecutionChange"]
    pub(crate) struct SignedBLSToExecutionChange<'a> {
        message: BLSToExecutionChange<'a>,
        signature: BLSSignature<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.ProposerSlashing"]
    pub(crate) struct ProposerSlashing<'a> {
        signed_header_1: SignedBeaconBlockHeader<'a>,
        signed_header_2: SignedBeaconBlockHeader<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.SigningData"]
    pub(crate) struct SigningData<'a> {
        object_root: Root<'a>,
        domain: Domain<'a>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.SyncAggregate"]
    pub(crate) struct SyncAggregate<'a> {
        sync_committee_bits: Binary<'a>,
        sync_committee_signature: BLSSignature<'a>,
    }
);

gen_struct!(
    #[derive(NifStruct)]
    #[module = "Types.Withdrawal"]
    pub(crate) struct Withdrawal<'a> {
        index: WithdrawalIndex,
        validator_index: ValidatorIndex,
        address: ExecutionAddress<'a>,
        amount: Gwei,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.ExecutionPayloadHeader"]
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
        base_fee_per_gas: Uint256<'a>,
        block_hash: Hash32<'a>,
        transactions_root: Root<'a>,
        withdrawals_root: Root<'a>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.ExecutionPayload"]
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
        base_fee_per_gas: Uint256<'a>,
        block_hash: Hash32<'a>,
        transactions: Vec<Transaction<'a>>,
        withdrawals: Vec<Withdrawal<'a>>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.ExecutionPayloadDeneb"]
    pub(crate) struct ExecutionPayloadDeneb<'a> {
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
        base_fee_per_gas: Uint256<'a>,
        block_hash: Hash32<'a>,
        transactions: Vec<Transaction<'a>>,
        withdrawals: Vec<Withdrawal<'a>>,
        blob_gas_used: u64,
        excess_blob_gas: u64,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.SyncCommittee"]
    pub(crate) struct SyncCommittee<'a> {
        pubkeys: Vec<BLSPubkey<'a>>,
        aggregate_pubkey: BLSPubkey<'a>,
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.BeaconState"]
    pub(crate) struct BeaconState<'a> {
        // Versioning
        genesis_time: u64,
        genesis_validators_root: Root<'a>,
        slot: Slot,
        fork: Fork<'a>,
        // History
        latest_block_header: BeaconBlockHeader<'a>,
        block_roots: Vec<Root<'a>>,
        state_roots: Vec<Root<'a>>,
        historical_roots: Vec<Root<'a>>, // Frozen in Capella, replaced by historical_summaries
        // Eth1
        eth1_data: Eth1Data<'a>,
        eth1_data_votes: Vec<Eth1Data<'a>>,
        eth1_deposit_index: u64,
        // Registry
        validators: Vec<Validator<'a>>,
        balances: Vec<Gwei>,
        // Randomness
        randao_mixes: Vec<Bytes32<'a>>,
        // Slashings
        slashings: Vec<Gwei>, // Per-epoch sums of slashed effective balances
        // Participation
        previous_epoch_participation: Vec<ParticipationFlags>,
        current_epoch_participation: Vec<ParticipationFlags>,
        // Finality
        justification_bits: Binary<'a>, // Bit set for every recent justified epoch
        previous_justified_checkpoint: Checkpoint<'a>,
        current_justified_checkpoint: Checkpoint<'a>,
        finalized_checkpoint: Checkpoint<'a>,
        // Inactivity
        inactivity_scores: Vec<u64>,
        // Sync
        current_sync_committee: SyncCommittee<'a>,
        next_sync_committee: SyncCommittee<'a>,
        // Execution
        latest_execution_payload_header: ExecutionPayloadHeader<'a>, // [Modified in Capella]
        // Withdrawals
        next_withdrawal_index: WithdrawalIndex, // [New in Capella]
        next_withdrawal_validator_index: ValidatorIndex, // [New in Capella]
        // Deep history valid from Capella onwards
        historical_summaries: Vec<HistoricalSummary<'a>>, // [New in Capella]
    }
);

gen_struct_with_config!(
    #[derive(NifStruct)]
    #[module = "Types.BeaconBlockBodyDeneb"]
    pub(crate) struct BeaconBlockBodyDeneb<'a> {
        randao_reveal: BLSSignature<'a>,
        eth1_data: Eth1Data<'a>,
        graffiti: Bytes32<'a>,
        proposer_slashings: Vec<ProposerSlashing<'a>>,
        attester_slashings: Vec<AttesterSlashing<'a>>,
        attestations: Vec<Attestation<'a>>,
        deposits: Vec<Deposit<'a>>,
        voluntary_exits: Vec<SignedVoluntaryExit<'a>>,
        sync_aggregate: SyncAggregate<'a>,
        execution_payload: ExecutionPayloadDeneb<'a>,
        bls_to_execution_changes: Vec<SignedBLSToExecutionChange<'a>>,
        blob_kzg_commitments: Vec<KZGCommitment<'a>>,
    }
);
