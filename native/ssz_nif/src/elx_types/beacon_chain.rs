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
    #[module = "SszTypes.HistoricalBatchMainnet"]
    pub(crate) struct HistoricalBatchMainnet<'a> {
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
