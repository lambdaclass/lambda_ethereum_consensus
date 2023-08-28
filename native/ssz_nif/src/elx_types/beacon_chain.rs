use super::*;
use crate::utils::gen_struct;
use rustler::{Binary, NifStruct};

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.Checkpoint"]
    pub(crate) struct Checkpoint<'a> {
        epoch: u64,
        root: Binary<'a>,
    }
);

// gen_struct!(
//     #[derive(NifStruct)]
//     #[module = "SszTypes.Fork"]
//     /// Corresponds to [`lighthouse_types::Fork`]
//     pub(crate) struct Fork<'a> {
//         previous_version: Binary<'a>,
//         current_version: Binary<'a>,
//         epoch: u64,
//     }
// );

// gen_struct!(
//     #[derive(NifStruct)]
//     #[module = "SszTypes.ForkData"]
//     /// Corresponds to [`lighthouse_types::ForkData`]
//     pub(crate) struct ForkData<'a> {
//         current_version: Binary<'a>,
//         genesis_validators_root: Binary<'a>,
//     }
// );

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

// gen_struct!(
//     #[derive(NifStruct)]
//     #[module = "SszTypes.AttestationData"]
//     /// Corresponds to [`lighthouse_types::AttestationData`]
//     pub(crate) struct AttestationData<'a> {
//         slot: u64,
//         index: u64,
//         beacon_block_root: Binary<'a>,
//         source: Checkpoint<'a>,
//         target: Checkpoint<'a>,
//     }
// );

// gen_struct!(
//     #[derive(NifStruct)]
//     #[module = "SszTypes.PendingAttestationMainnet"]
//     /// Corresponds to [`lighthouse_types::PendingAttestation`]
//     /// with `T` = [`lighthouse_types::MainnetEthSpec`]
//     pub(crate) struct PendingAttestationMainnet<'a> {
//         aggregation_bits: Binary<'a>,
//         data: AttestationData<'a>,
//         inclusion_delay: u64,
//         proposer_index: u64,
//     }
// );

// gen_struct!(
//     #[derive(NifStruct)]
//     #[module = "SszTypes.Eth1Data"]
//     /// Corresponds to [`lighthouse_types::Eth1Data`]
//     pub(crate) struct Eth1Data<'a> {
//         deposit_root: Binary<'a>,
//         deposit_count: u64,
//         block_hash: Binary<'a>,
//     }
// );

// gen_struct!(
//     #[derive(NifStruct)]
//     #[module = "SszTypes.HistoricalBatchMainnet"]
//     /// Corresponds to [`lighthouse_types::HistoricalBatch`]
//     /// with `T` = [`lighthouse_types::MainnetEthSpec`]
//     pub(crate) struct HistoricalBatchMainnet<'a> {
//         block_roots: Vec<Binary<'a>>,
//         state_roots: Vec<Binary<'a>>,
//     }
// );

// gen_struct!(
//     #[derive(NifStruct)]
//     #[module = "SszTypes.HistoricalBatchMinimal"]
//     /// Corresponds to [`lighthouse_types::HistoricalBatch`]
//     /// with `T` = [`lighthouse_types::MinimalEthSpec`]
//     pub(crate) struct HistoricalBatchMinimal<'a> {
//         block_roots: Vec<Binary<'a>>,
//         state_roots: Vec<Binary<'a>>,
//     }
// );

// gen_struct!(
//     #[derive(NifStruct)]
//     #[module = "SszTypes.DepositData"]
//     /// Corresponds to [`lighthouse_types::DepositData`]
//     pub(crate) struct DepositData<'a> {
//         pubkey: Binary<'a>,
//         withdrawal_credentials: Binary<'a>,
//         amount: u64,
//         signature: Binary<'a>,
//     }
// );

// gen_struct!(
//     #[derive(NifStruct)]
//     #[module = "SszTypes.VoluntaryExit"]
//     /// Corresponds to [`lighthouse_types::VoluntaryExit`]
//     pub(crate) struct VoluntaryExit {
//         epoch: u64,
//         validator_index: u64,
//     }
// );

// gen_struct!(
//     #[derive(NifStruct)]
//     #[module = "SszTypes.Deposit"]
//     /// Corresponds to [`lighthouse_types::Deposit`]
//     pub(crate) struct Deposit<'a> {
//         proof: Vec<Binary<'a>>,
//         data: DepositData<'a>,
//     }
// );

// gen_struct!(
//     #[derive(NifStruct)]
//     #[module = "SszTypes.DepositMessage"]
//     /// Corresponds to [`lighthouse_types::DepositMessage`]
//     pub(crate) struct DepositMessage<'a> {
//         pubkey: Binary<'a>,
//         withdrawal_credentials: Binary<'a>,
//         amount: u64,
//     }
// );

gen_struct!(
    #[derive(NifStruct)]
    #[module = "SszTypes.HistoricalSummary"]
    pub(crate) struct HistoricalSummary<'a> {
        pub(crate) block_summary_root: Root<'a>,
        pub(crate) state_summary_root: Root<'a>,
    }
);
