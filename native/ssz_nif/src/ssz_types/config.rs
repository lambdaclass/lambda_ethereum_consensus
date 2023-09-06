use ssz_types::typenum::{self, Unsigned};

pub(crate) trait Config {
    type SyncCommitteeSize: Unsigned;
    type MaxValidatorsPerCommittee: Unsigned;
    type SlotsPerHistoricalRoot: Unsigned;
    type DepositContractTreeDepth: Unsigned;
    type BytesPerLogsBloom: Unsigned;
    type MaxExtraDataBytes: Unsigned;
    type MaxTransactionsPerPayload: Unsigned;
    type MaxWithdrawalsPerPayload: Unsigned;
}

pub(crate) struct Mainnet;

impl Config for Mainnet {
    type SyncCommitteeSize = typenum::U512;
    type MaxValidatorsPerCommittee = typenum::U2048;
    type SlotsPerHistoricalRoot = typenum::U8192;
    type DepositContractTreeDepth = typenum::U33;
    type BytesPerLogsBloom = typenum::U256;
    type MaxExtraDataBytes = typenum::U32;
    type MaxTransactionsPerPayload = typenum::U1048576;
    type MaxWithdrawalsPerPayload = typenum::U16;
}

pub(crate) struct Minimal;

impl Config for Minimal {
    type SyncCommitteeSize = typenum::U32;
    type MaxValidatorsPerCommittee = typenum::U2048;
    type SlotsPerHistoricalRoot = typenum::U64;
    type DepositContractTreeDepth = typenum::U33;
    type BytesPerLogsBloom = typenum::U256;
    type MaxExtraDataBytes = typenum::U32;
    type MaxTransactionsPerPayload = typenum::U1048576;
    type MaxWithdrawalsPerPayload = typenum::U16;
}
